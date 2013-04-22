#import "STKStackManager.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"

#import <objc/runtime.h>

#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBApplicationIcon.h>
#import <SpringBoard/SBRootFolder.h>
#import <SpringBoard/SBIconModel.h>
#import <SpringBoard/SBIconViewMap.h>
#import <SpringBoard/SBIconView.h>
#import <SpringBoard/SBIconImageView.h>
#import <SpringBoard/SBIconListView.h>
#import <SpringBoard/SBDockIconListView.h>

static NSString * const STKStackTopIconsKey    = @"topicons";
static NSString * const STKStackBottomIconsKey = @"bottomicons";
static NSString * const STKStackLeftIconsKey   = @"lefticons";
static NSString * const STKStackRightIconsKey  = @"righticons";

#define kEnablingThreshold   55
#define kMaximumDisplacement 85
#define kAnimationDuration   0.2
#define kDisabledIconAlpha   0.2
#define kBandingAllowance    12 // Allow for the icons to stretch for up to 12 points beyond their target locations
#define kBandingFactor       0.6 // factor by which distance must be multipled after it crosses the threshold


#pragma mark - Private Method Declarations
@interface STKStackManager ()
{
    SBIcon               *_centralIcon;
    STKIconLayout        *_appearingIconsLayout;
    STKIconLayout        *_disappearingIconsLayout;
    STKIconLayoutHandler *_handler;
    NSMapTable           *_iconViewsTable;
    STKInteractionHandler _interactionHandler;

    CGFloat               _targetDistance;

    CGFloat               _lastDistanceFromCenter;
    BOOL                  _hasPreparedGhostlyIcons;
}

- (void)_animateToOpenPosition;
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock;

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance;

- (SBIconView *)_getIconViewForIcon:(SBIcon *)icon;
- (STKPositionMask)_locationMaskForIcon:(SBIcon *)icon;

// Returns the target origin for icons in the stack at the moment.
- (CGPoint)_getTargetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance;

// This method manually calculates where the displaced icons should go. Index is the index of the icon from the central icon, with the furthest starting from zero.
- (CGPoint)_getDisplacedOriginForIcon:(SBIcon *)icon atIndex:(NSUInteger)index withPosition:(STKLayoutPosition)position;

// Returns the distance of a point from the central icon's centre, calculated using distance formula
- (CGFloat)_distanceFromCentre:(CGPoint)centre;

- (void)_makeAllIconsPerformBlock:(void(^)(SBIcon *))block; // Includes icons in dock

- (NSArray *)_appearingIconsForPosition:(STKLayoutPosition)position;

// Alpha shit
- (void)_setAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral disableInteraction:(BOOL)disableInteraction;
- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral disableInteraction:(BOOL)disableInteraction;
- (void)_setInteractionEnabled:(BOOL)enabled forAllIconsExcludingCentral:(BOOL)excludeCentral;
- (void)_setPageControlAlpha:(CGFloat)alpha;
- (CGFloat)_alphaForDistance:(CGFloat)distance maxDistance:(CGFloat)maxDistance minimumAlpha:(CGFloat)minAlpha;

@end


@implementation STKStackManager 

// Make the property use this ivar
@synthesize currentIconDistance = _lastDistanceFromCenter;

#pragma mark - Public Methods
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons
{
    if ((self = [super init])) {
        [icons retain]; // Make sure it's not released until we're done with it

        _centralIcon             = [centralIcon retain];
        _handler                 = [[STKIconLayoutHandler alloc] init];
        _appearingIconsLayout    = [[_handler layoutForIcons:icons aroundIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
        _disappearingIconsLayout = [[_handler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconsLayout] retain];
        _iconViewsTable          = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory capacity:4];

        CLog(@"CPU Frequency: %u", STKGetCPUFrequency());

        [icons release];
    }
    return self;
}

- (void)dealloc
{
    if (_hasSetup) {
        // Remove the icon views if they're in superviews...
        // Don't want shit hanging around
        for (NSArray *iconViews in [[_iconViewsTable objectEnumerator] allObjects]) {
            for (SBIconView *iconView in iconViews) {
                [iconView removeFromSuperview];
            }
        }
    }

    [_centralIcon release];
    [_handler release];
    [_interactionHandler release];
    [_appearingIconsLayout release];
    [_disappearingIconsLayout release];
    [_iconViewsTable release];

    [super dealloc];
}

- (id)init
{
    NSAssert(NO, @"You MUST use -[STKStackManager initWithCentralIcon:stackIcons:]");
    return nil;
}

#pragma mark - Adding Stack Icons
- (void)setupViewIfNecessary
{
    if (!_hasSetup) {
        [self setupView];
    }
}

- (void)setupView
{
    if (!_iconViewsTable) {
        _iconViewsTable = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory capacity:4];
    }

    [_appearingIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
        SBIconView *iconView = [[[objc_getClass("SBIconView") alloc] initWithDefaultSize] autorelease];
        [iconView setIcon:icon];
        [iconView setDelegate:self];
        SBIconListView *listView = STKListViewForIcon(_centralIcon);

        SBIconView *centralIconView = [self _getIconViewForIcon:_centralIcon];
        [iconView setFrame:centralIconView.frame];

        [listView insertSubview:iconView belowSubview:centralIconView];

        NSString *mapTableKey = nil;
        switch (position) {
            case STKLayoutPositionTop:
                mapTableKey = STKStackTopIconsKey;
                break;

            case STKLayoutPositionBottom:
                mapTableKey = STKStackBottomIconsKey;
                break;

            case STKLayoutPositionLeft:
                mapTableKey = STKStackLeftIconsKey;
                break;

            case STKLayoutPositionRight:
                mapTableKey = STKStackRightIconsKey;
                break;
        }
        NSMutableArray *iconViews = [_iconViewsTable objectForKey:mapTableKey];
        if (!iconViews) {
            iconViews = [NSMutableArray array];
        }
        [iconViews addObject:iconView];
        [_iconViewsTable setObject:iconViews forKey:mapTableKey];
    }];
    
    _targetDistance = ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) ? 76.0f : 86.0f); // Calculate the target distance here, no need to do it every time. I doubt the interface idiom is going to change every time this is  called.

    _hasSetup = YES;
}

#pragma mark - Moving Icons
- (void)touchesDraggedForDistance:(CGFloat)distance
{
    if (_isExpanded) {
        return;
    }

    if (!_hasPreparedGhostlyIcons) {
        [[objc_getClass("SBIconController") sharedInstance] prepareToGhostCurrentPageIconsForRequester:2 skipIcon:_centralIcon];
    }

    [self _moveAllIconsInRespectiveDirectionsByDistance:distance];
    [self _setGhostlyAlphaForAllIcons:STKAlphaFromDistance(_lastDistanceFromCenter) excludingCentralIcon:YES disableInteraction:YES];
}

- (void)touchesEnded
{
    if (_lastDistanceFromCenter >= kEnablingThreshold && (!_isExpanded)) {
        [[objc_getClass("SBIconController") sharedInstance] setCurrentPageIconsGhostly:YES forRequester:2 skipIcon:_centralIcon];
        [self _animateToOpenPosition];
    }
    else {
        [self closeStack];
    }
}
 
- (void)closeStackWithCompletionHandler:(void(^)(void))completionHandler
{
    [self _animateToClosedPositionWithCompletionBlock:^{
        if (completionHandler) {
            completionHandler();
        }
    }];
}

- (void)closeStackSettingCentralIcon:(SBIcon *)icon completion:(void(^)(void))handler
{
    SBIconView *centralIconView = [self _getIconViewForIcon:_centralIcon];

    [centralIconView setIcon:icon];
    
    [self closeStackWithCompletionHandler:^{
        if (handler) {
            handler();
        }
        EXECUTE_BLOCK_AFTER_DELAY(0.25, ^{
            // Okay, this is a hack, and not really OOP compliant. The 0.25 second delay is given so that when handler() launches an app, the central icon doesn't flash back quickly to the original
            [centralIconView setIcon:_centralIcon];
        });
    }];
}

- (void)closeStack
{
    [self closeStackWithCompletionHandler:nil];
}

#pragma mark - Open Completion Animation
- (void)_animateToOpenPosition
{
    [UIView animateWithDuration:kAnimationDuration animations:^{
        [(NSArray *)[_iconViewsTable objectForKey:STKStackTopIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionTop distanceFromCentre:idx + 1];
            iconView.frame = newFrame;
        }];

        [(NSArray *)[_iconViewsTable objectForKey:STKStackBottomIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionBottom distanceFromCentre:idx + 1];
            iconView.frame = newFrame;
        }];

        [(NSArray *)[_iconViewsTable objectForKey:STKStackLeftIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionLeft distanceFromCentre:idx + 1];
            iconView.frame = newFrame;
        }];

        [(NSArray *)[_iconViewsTable objectForKey:STKStackRightIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionRight distanceFromCentre:idx + 1];
            iconView.frame = newFrame;
        }];

        [_disappearingIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
            SBIconView *iconView = [self _getIconViewForIcon:icon];
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _getDisplacedOriginForIcon:icon atIndex:index withPosition:position];
            iconView.frame = newFrame;
        }];
        
    } completion:^(BOOL finished) {
        if (finished) {
            _isExpanded = YES;
        }
    }];
}

#pragma mark - Close Animation
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock
{
    [UIView animateWithDuration:kAnimationDuration animations:^{
        // Set the frame for all these icons to the frame of their central icon
        for (NSArray *iconViews in [[_iconViewsTable objectEnumerator] allObjects]) {
            for (SBIconView *iconView in iconViews) {
                iconView.frame = [self _getIconViewForIcon:_centralIcon].frame;
                iconView.alpha = 0.f;
            }
        }

        // Move all icons to their respective locations
        SBIconListView *listView = STKListViewForIcon(_centralIcon);
        [listView setIconsNeedLayout];
        [listView layoutIconsIfNeeded:kAnimationDuration domino:YES];
        [self _setGhostlyAlphaForAllIcons:1.0f excludingCentralIcon:YES disableInteraction:NO];
        
        [[objc_getClass("SBIconController") sharedInstance] cleanUpGhostlyIconsForRequester:2];
        _hasPreparedGhostlyIcons = NO;

    } completion:^(BOOL finished) {
        if (finished) {
            _isExpanded = NO;
            if (completionBlock) {
                completionBlock();
            }
        }
    }];
}

#pragma mark - Move ALL the things
- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance
{
    CGFloat horizontalBandingAllowance = kBandingAllowance + 10; // The vertical and horizontal icons don't reach their targets at the same time, hence allow for more banding horizontally

    // Move icons currently on display to make way for stack icons
    [_disappearingIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];
        SBIconView *iconView = [self _getIconViewForIcon:icon];
        CGRect newFrame = iconView.frame;
        CGPoint originalOrigin = [listView originForIcon:icon];
        CGPoint targetOrigin = [self _getDisplacedOriginForIcon:icon atIndex:index withPosition:position];

        CGFloat factoredDistance = (distance * [self _appearingIconsForPosition:position].count);

        switch (position) {
            case STKLayoutPositionTop: {
                targetOrigin.y -= kBandingAllowance;
                if ((newFrame.origin.y - factoredDistance) < targetOrigin.y) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.y - factoredDistance) > originalOrigin.y) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.y -= factoredDistance;
                }
                break;
            }
            case STKLayoutPositionBottom: {
                targetOrigin.y += kBandingAllowance;
                if ((newFrame.origin.y + factoredDistance) > targetOrigin.y) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.y + factoredDistance) < originalOrigin.y) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.y += factoredDistance;
                }
                break;
            }
            case STKLayoutPositionLeft: {
                targetOrigin.x -= horizontalBandingAllowance;
                if ((newFrame.origin.x - factoredDistance) < targetOrigin.x) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.x - factoredDistance) > originalOrigin.x) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.x -= factoredDistance;
                }
                break;
            }
            case STKLayoutPositionRight: {
                targetOrigin.x += horizontalBandingAllowance;
                if ((newFrame.origin.x + factoredDistance) > targetOrigin.x) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.x + factoredDistance) < originalOrigin.x) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.x += factoredDistance;
                }
                break;
            }
        }
        iconView.frame = newFrame;
        CLog(@"Moved icons by distance: %.2f", factoredDistance);
    }];

    // Move stack icons
    CGRect centralFrame = [self _getIconViewForIcon:_centralIcon].frame;

    [(NSArray *)[_iconViewsTable objectForKey:STKStackTopIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        if (idx == 0) {
            _lastDistanceFromCenter = [self _distanceFromCentre:iconView.center];
        }
        CGFloat translatedDistance = distance * (idx + 1);
        
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionTop distanceFromCentre:idx + 1];
        targetOrigin.y -= kBandingAllowance;
        iconView.alpha = 1.f;

        
        if (((newFrame.origin.y - translatedDistance) > targetOrigin.y) && (!((newFrame.origin.y - translatedDistance) > centralFrame.origin.y))) {
            newFrame.origin.y -= translatedDistance;
        }
        // If it's going beyond the acceptable limit, make it stick to the max position. The same thing is done in all the arrays below
        else if ((newFrame.origin.y - translatedDistance) < targetOrigin.y) {
            newFrame.origin = targetOrigin;
        }
        else if ((newFrame.origin.y - translatedDistance) > centralFrame.origin.y) {
            newFrame = [self _getIconViewForIcon:_centralIcon].frame;
        }
        iconView.frame = newFrame;
    }];

    [(NSArray *)[_iconViewsTable objectForKey:STKStackBottomIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        if (idx == 0) {
            _lastDistanceFromCenter = [self _distanceFromCentre:iconView.center];
        }
        CGFloat translatedDistance = distance * (idx + 1);
        
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionBottom distanceFromCentre:idx + 1];
        targetOrigin.y += kBandingAllowance;
        iconView.alpha = 1.f;
        
        if ((newFrame.origin.y + translatedDistance) < targetOrigin.y && (!((newFrame.origin.y + translatedDistance) < centralFrame.origin.y))) {
            newFrame.origin.y += translatedDistance;
        }
        else if ((newFrame.origin.y + translatedDistance) > targetOrigin.y) {
            newFrame.origin = targetOrigin;
        }
        else if ((newFrame.origin.y + translatedDistance) < centralFrame.origin.y) {
            newFrame = centralFrame;
        }
        iconView.frame = newFrame;
    }];

    [(NSArray *)[_iconViewsTable objectForKey:STKStackLeftIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        if (idx == 0) {
            _lastDistanceFromCenter = [self _distanceFromCentre:iconView.center];
        }
        CGFloat translatedDistance = distance * (idx + 1);
        
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionLeft distanceFromCentre:idx + 1];
        targetOrigin.x -= horizontalBandingAllowance;

        
        iconView.alpha = 1.f;
        
        if (((newFrame.origin.x - translatedDistance) > targetOrigin.x) && (!((newFrame.origin.x - translatedDistance) > centralFrame.origin.x))) {
            newFrame.origin.x -= translatedDistance;
        }
        else if ((newFrame.origin.x - translatedDistance) < targetOrigin.x) {
            newFrame.origin = targetOrigin;
        }
        else if ((newFrame.origin.x - translatedDistance) > centralFrame.origin.x) {
            newFrame = centralFrame;
        }
        iconView.frame = newFrame;
    }];

    [(NSArray *)[_iconViewsTable objectForKey:STKStackRightIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        if (idx == 0) {
            _lastDistanceFromCenter = [self _distanceFromCentre:iconView.center];
        }
        CGFloat translatedDistance = distance * (idx + 1);
        
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionRight distanceFromCentre:idx + 1];
        targetOrigin.x += horizontalBandingAllowance;
        
        iconView.alpha = 1.f;
        
        if (((newFrame.origin.x + translatedDistance) < targetOrigin.x) && (!((newFrame.origin.x + translatedDistance) < centralFrame.origin.x))) {
            newFrame.origin.x += translatedDistance;
        }
        else if ((newFrame.origin.x + translatedDistance) > targetOrigin.x) {
            newFrame.origin = targetOrigin;
        }
        else if ((newFrame.origin.x + translatedDistance) < centralFrame.origin.x) {
            newFrame = centralFrame;
        }
        iconView.frame = newFrame;
    }];
}

#pragma mark - Helper Methods
- (SBIconView *)_getIconViewForIcon:(SBIcon *)icon
{
    return [[objc_getClass("SBIconViewMap") homescreenMap] iconViewForIcon:icon];
}

- (STKPositionMask)_locationMaskForIcon:(SBIcon *)icon
{
    STKPositionMask mask = 0x0;
    
    if (!icon) {
        return mask;
    }

    STKIconLayoutHandler *handler = [[STKIconLayoutHandler alloc] init];
    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    STKIconCoordinates *coordinates = [handler copyCoordinatesForIcon:icon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    [handler release];

    CLog(@"Coordinates: {x: %i, y: %i, index: %i} maxRows: %i, maxColumns:%i", coordinates->xPos, coordinates->yPos, coordinates->index, [listView iconRowsForCurrentOrientation], [listView iconColumnsForCurrentOrientation]);

    if (coordinates->xPos == 0) {
        mask |= STKPositionTouchingLeft;
    }
    if (coordinates->xPos == ([listView iconColumnsForCurrentOrientation] - 1)) {
        mask |= STKPositionTouchingRight;
    }
    if (coordinates->yPos == 0) {
        mask |= STKPositionTouchingTop;
    }
    if (coordinates->yPos == ([listView iconRowsForCurrentOrientation] - 1)) {
        mask |= STKPositionTouchingBottom;
    }

    free(coordinates);

    return mask;
    
}

- (CGPoint)_getTargetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance
{
    STKIconCoordinates *centralCoords = [_handler copyCoordinatesForIcon:_centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];

    CGPoint ret = CGPointZero;

    switch (position) {
        case STKLayoutPositionTop: {
            NSUInteger newY = (centralCoords->yPos - distance); // New Y will be `distance` units above original y
            ret =  [listView originForIconAtX:centralCoords->xPos Y:newY];
            break;
        }
        case STKLayoutPositionBottom: {
            NSUInteger newY = (centralCoords->yPos + distance); // New Y will be below
            ret = [listView originForIconAtX:centralCoords->xPos Y:newY]; 
            break;
        }
        case STKLayoutPositionLeft: {
            NSUInteger newX = (centralCoords->xPos - distance); // New X has to be `distance` points to left, so subtract
            ret = [listView originForIconAtX:newX Y:centralCoords->yPos];
            break;
        }
        case STKLayoutPositionRight: {
            NSUInteger newX = (centralCoords->xPos + distance); // Inverse of previous, hence add to original coordinate
            ret = [listView originForIconAtX:newX Y:centralCoords->yPos];
            break;
        }
    }

    free(centralCoords);
    return ret;
}

- (CGPoint)_getDisplacedOriginForIcon:(SBIcon *)icon atIndex:(NSUInteger)index withPosition:(STKLayoutPosition)position
{
    // Calculate the positions manually, as -[SBIconListView originForIconAtX:Y:] only gives coordinates that will be on screen.
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];
    SBIconView *iconView = [self _getIconViewForIcon:icon];
    
    CGPoint originalOrigin = [listView originForIcon:icon]; // Use the original location as a reference, as the iconview might have been displaced.
    CGRect originalFrame = (CGRect){{originalOrigin.x, originalOrigin.y}, {iconView.frame.size.width, iconView.frame.size.height}};
    
    CGPoint returnPoint;
    NSArray *currentArray = ((position == STKLayoutPositionTop) ? _appearingIconsLayout.topIcons : (position == STKLayoutPositionBottom) ? _appearingIconsLayout.bottomIcons : (position == STKLayoutPositionLeft) ? _appearingIconsLayout.leftIcons : _appearingIconsLayout.rightIcons); // I LOVE THIS 

    NSInteger multiplicationFactor = currentArray.count;
    
    switch (position) {
        case STKLayoutPositionTop: {
            returnPoint.x = originalFrame.origin.x;
            returnPoint.y = originalFrame.origin.y - ((originalFrame.size.height + [listView verticalIconPadding]) * multiplicationFactor);
            break;
        }
        case STKLayoutPositionBottom: {
            returnPoint.x = originalFrame.origin.x;
            returnPoint.y = originalFrame.origin.y + ((originalFrame.size.height + [listView verticalIconPadding]) * multiplicationFactor);    
            break;
        }
        case STKLayoutPositionLeft: {
            returnPoint.y = originalFrame.origin.y;
            returnPoint.x = originalFrame.origin.x - ((originalFrame.size.width + [listView horizontalIconPadding]) * multiplicationFactor);
            break;
        }
        case STKLayoutPositionRight: {
            returnPoint.y = originalFrame.origin.y;
            returnPoint.x = originalFrame.origin.x + ((originalFrame.size.width + [listView horizontalIconPadding]) * multiplicationFactor);
            break;
        }
    }
    
    return returnPoint;
}

- (void)_makeAllIconsPerformBlock:(void(^)(SBIcon *))block
{
    if (!block) {
        return;
    }

    SBIconListView *currentListView = STKListViewForIcon(_centralIcon);
    for (SBIcon *icon in currentListView.icons) {
        block(icon);
    }
    
    SBDockIconListView *dockView = [[objc_getClass("SBIconController") sharedInstance] dock];
    for (SBIcon *icon in dockView.icons) {    
        block(icon);
    }
}

- (NSArray *)_appearingIconsForPosition:(STKLayoutPosition)position
{
    return ((position == STKLayoutPositionTop) ? _appearingIconsLayout.topIcons : (position == STKLayoutPositionBottom) ? _appearingIconsLayout.bottomIcons : (position == STKLayoutPositionLeft) ? _appearingIconsLayout.leftIcons : _appearingIconsLayout.rightIcons);   
}

- (CGFloat)_distanceFromCentre:(CGPoint)point
{
    SBIconView *iconView = [self _getIconViewForIcon:_centralIcon];
    return sqrtf(((point.x - iconView.center.x) * (point.x - iconView.center.x)) + ((point.y - iconView.center.y)  * (point.y - iconView.center.y))); // distance formula
}

#pragma mark - Alpha Shit
- (void)_setAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)shouldExcludeCentral disableInteraction:(BOOL)disableInteraction
{
    [self _makeAllIconsPerformBlock:^(SBIcon *icon) {
        if (shouldExcludeCentral && ([icon.leafIdentifier isEqualToString:_centralIcon.leafIdentifier])) {
            return;
        }
        SBIconView *iconView = [self _getIconViewForIcon:icon];
        iconView.alpha = alpha;
        iconView.userInteractionEnabled = !disableInteraction;
    }];
}

- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral disableInteraction:(BOOL)disableInteraction
{
    [self _setInteractionEnabled:!(disableInteraction) forAllIconsExcludingCentral:excludeCentral];
    [[objc_getClass("SBIconController") sharedInstance] setCurrentPageIconsPartialGhostly:alpha forRequester:2 skipIcon:(excludeCentral ? _centralIcon : nil)];
}

- (void)_setInteractionEnabled:(BOOL)enabled forAllIconsExcludingCentral:(BOOL)shouldExcludeCentral
{
    [self _makeAllIconsPerformBlock:^(SBIcon *icon) {
        if (shouldExcludeCentral && ([icon.leafIdentifier isEqualToString:_centralIcon.leafIdentifier])) {
            return;
        }
        SBIconView *iconView = [self _getIconViewForIcon:icon];
        iconView.userInteractionEnabled = enabled;
    }];
}

- (void)_setPageControlAlpha:(CGFloat)alpha
{

}

- (CGFloat)_alphaForDistance:(CGFloat)distance maxDistance:(CGFloat)maxDistance minimumAlpha:(CGFloat)minAlpha
{
    return STKScaleNumber(distance, 0, maxDistance, 1.0, minAlpha);
}

#pragma mark - SBIconViewDelegate
- (void)iconTapped:(SBIconView *)iconView
{
    iconView.highlighted = YES;
    if (_interactionHandler) {
        _interactionHandler(iconView);
    }
    iconView.highlighted = NO;
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return YES;
}

- (BOOL)iconPositionIsEditable:(SBIconView *)iconView
{
    return NO;
}

- (BOOL)iconAllowJitter:(SBIconView *)iconView
{
    return NO;
}

@end
