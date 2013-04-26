#import "STKStackManager.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "substrate.h"

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
#define kBandingAllowance    ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) ? 15 : 30)
#define kGhostlyRequesterID  1 


#pragma mark - Private Method Declarations
@interface STKStackManager ()
{
    SBIcon                *_centralIcon;
    STKIconLayout         *_appearingIconsLayout;
    STKIconLayout         *_disappearingIconsLayout;
    STKIconLayoutHandler  *_handler;
    NSMapTable            *_iconViewsTable;
    STKInteractionHandler  _interactionHandler;

    CGFloat                _distanceRatio;
    STKIconLayout         *_offScreenIconsLayout;

    CGFloat                _lastDistanceFromCenter;
    BOOL                   _hasPreparedGhostlyIcons;

    UISwipeGestureRecognizer *_swipeRecognizer;
}

- (void)_animateToOpenPosition;
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock;

- (void)_handleCloseGesture:(UISwipeGestureRecognizer *)sender; // this is the default action for both swipe
- (void)_cleanupGestureRecognizer;

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance;

- (SBIconView *)_getIconViewForIcon:(SBIcon *)icon;
- (STKPositionMask)_locationMaskForIcon:(SBIcon *)icon;

// Returns the target origin for icons in the stack at the moment.
- (CGPoint)_getTargetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance;

// Manually calculates where the displaced icons should go.
- (CGPoint)_getDisplacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position;

// Returns the distance of a point from the central icon's centre, calculated using distance formula
- (CGFloat)_distanceFromCentre:(CGPoint)centre;

- (void)_makeAllIconsPerformBlock:(void(^)(SBIcon *))block; // Includes icons in dock

- (NSArray *)_appearingIconsForPosition:(STKLayoutPosition)position;

- (void)_calculateDistanceRatio;
- (void)_findIconsWithOffScreenTargets;

// Alpha shit
- (void)_setAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)shouldExcludeCentral disableInteraction:(BOOL)disableInteraction;

// This sexy method disables/enables icon interaction as required.
- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral; 

// Applies it to the shadow and label of the appearing icons
- (void)_setAlphaForAppearingLabelsAndShadows:(CGFloat)alpha;

- (void)_setInteractionEnabled:(BOOL)enabled forAllIconsExcludingCentral:(BOOL)excludeCentral;
- (void)_setPageControlAlpha:(CGFloat)alpha;

@end


@implementation STKStackManager 

// Make the property use this ivar
@synthesize currentIconDistance = _lastDistanceFromCenter;

static BOOL __isStackOpen;
static BOOL __stackInMotion;

+ (BOOL)anyStackOpen
{
    return __isStackOpen;
}

+ (BOOL)anyStackInMotion
{
    return __stackInMotion;
}

#pragma mark - Public Methods
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons
{
    if ((self = [super init])) {
        [icons retain]; // Make sure it's not released until we're done with it

        _centralIcon             = [centralIcon retain];
        _handler                 = [[STKIconLayoutHandler alloc] init];
        _appearingIconsLayout    = [[_handler layoutForIcons:icons aroundIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
        _disappearingIconsLayout = [[_handler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconsLayout] retain];

        [icons release];

        [self _calculateDistanceRatio];
        [self _findIconsWithOffScreenTargets];
    }
    return self;
}

- (void)dealloc
{
    if (_hasSetup) {
        // Remove the icon views from the list view.
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
    [_offScreenIconsLayout release];

    [self _cleanupGestureRecognizer];

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

    [_appearingIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconView *iconView = [[[objc_getClass("SBIconView") alloc] initWithDefaultSize] autorelease];
        [iconView setIcon:icon];
        [iconView setDelegate:self];
        SBIconListView *listView = STKListViewForIcon(_centralIcon);

        SBIconView *centralIconView = [self _getIconViewForIcon:_centralIcon];
        [iconView setFrame:centralIconView.frame];

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
        [iconView setIconLabelAlpha:0.f];
        [[iconView valueForKeyPath:@"_shadow"] setAlpha:0.f];
        [listView insertSubview:iconView belowSubview:((index == 1) ? iconViews[0] : centralIconView)];
        // If the current icon is the second icon, add it below the previous one, so it slides out from ***under*** it.
    }];

    _hasSetup = YES;
}

#pragma mark - Moving Icons
- (void)touchesDraggedForDistance:(CGFloat)distance
{
    if (_isExpanded) {
        return;
    }

    if (!_hasPreparedGhostlyIcons) {
        [[objc_getClass("SBIconController") sharedInstance] prepareToGhostCurrentPageIconsForRequester:kGhostlyRequesterID skipIcon:_centralIcon];
        _hasPreparedGhostlyIcons = YES;
    }
    __stackInMotion = YES;
    [self _moveAllIconsInRespectiveDirectionsByDistance:distance];
    
    CGFloat alpha = STKAlphaFromDistance(_lastDistanceFromCenter);
    [self _setGhostlyAlphaForAllIcons:alpha excludingCentralIcon:YES];
    [self _setAlphaForAppearingLabelsAndShadows:(1 - alpha)];
    [self _setPageControlAlpha:alpha];  
    
    __stackInMotion = NO;
}

- (void)touchesEnded
{
    if (_lastDistanceFromCenter >= kEnablingThreshold && (!_isExpanded)) {
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

- (void)openStack
{
    [self _animateToOpenPosition];
}

- (void)closeStack
{
    [self closeStackWithCompletionHandler:nil];
}

- (void)closeStackAfterDelay:(NSTimeInterval)delay completion:(void(^)(void))completionBlock
{
    EXECUTE_BLOCK_AFTER_DELAY(delay, ^{
        [self closeStackWithCompletionHandler:completionBlock];
    });
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
            newFrame.origin = [self _getDisplacedOriginForIcon:icon withPosition:position];
            iconView.frame = newFrame;
        }];

        [self _setPageControlAlpha:0];
        [self _setGhostlyAlphaForAllIcons:0.f excludingCentralIcon:YES];
        [self _setAlphaForAppearingLabelsAndShadows:1];

        [_offScreenIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition pos) {
            [self _getIconViewForIcon:icon].alpha = 0.f;
        }];
        
    } completion:^(BOOL finished) {
        if (finished) {
            _isExpanded = YES;
            __isStackOpen = YES;

            // Add gesture recognizers...
            // Store references to them in ivars, so as to get rid of them when a gesture is recognized!
            _swipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(_handleCloseGesture:)];
            _swipeRecognizer.direction = (UISwipeGestureRecognizerDirectionUp | UISwipeGestureRecognizerDirectionDown);

            UIView *contentView = [[objc_getClass("SBUIController") sharedInstance] contentView];
            [contentView addGestureRecognizer:_swipeRecognizer];
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

        // Set the alphas back to original
        [self _setGhostlyAlphaForAllIcons:.9999999f excludingCentralIcon:NO]; // .999f is necessary, unfortunately. A weird 1.0->0.0->1.0 alpha flash happens otherwise
        [self _setGhostlyAlphaForAllIcons:1.f excludingCentralIcon:NO]; // Set it back to 1.f, fix a pain in the ass bug
        [self _setAlphaForAppearingLabelsAndShadows:0];
        [self _setPageControlAlpha:1];

        // Bring the off screen icons back to life! :D
        [_offScreenIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition pos) {
            [self _getIconViewForIcon:icon].alpha = 1.f;
        }];
        
        [[objc_getClass("SBIconController") sharedInstance] cleanUpGhostlyIconsForRequester:kGhostlyRequesterID];
        _hasPreparedGhostlyIcons = NO;

    } completion:^(BOOL finished) {
        if (finished) {
            _isExpanded = NO;
            __isStackOpen = NO;
                                                                     
            if (completionBlock) {
                completionBlock();
            }
        }
    }];

    // Move all icons to their respective locations
    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    [listView setIconsNeedLayout];
    [listView layoutIconsIfNeeded:kAnimationDuration domino:NO];

    _lastDistanceFromCenter = 0.f;

    // Remove recognizers if they're still around
    [self _cleanupGestureRecognizer];
}

- (void)_handleCloseGesture:(UIGestureRecognizer *)sender
{
    [self _cleanupGestureRecognizer];
    [self closeStackWithCompletionHandler:^{ if (_interactionHandler) _interactionHandler(nil); }];
}

- (void)_cleanupGestureRecognizer
{
    [_swipeRecognizer.view removeGestureRecognizer:_swipeRecognizer];
    [_swipeRecognizer release];
    _swipeRecognizer = nil;
}

#pragma mark - Move ALL the things
- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance
{
    // Move icons currently on display to make way for stack icons
    [_disappearingIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];
        SBIconView *iconView = [self _getIconViewForIcon:icon];
        CGRect newFrame = iconView.frame;
        CGPoint originalOrigin = [listView originForIcon:icon];
        CGPoint targetOrigin = [self _getDisplacedOriginForIcon:icon withPosition:position];

        CGFloat factoredDistance = (distance * [self _appearingIconsForPosition:position].count);
        CGFloat horizontalFactoredDisance = factoredDistance * _distanceRatio; // The distance to be moved horizontally is slightly more different than vertical, multiply it by the ratio to have them work perfectly. :)

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
                targetOrigin.x -= kBandingAllowance * _distanceRatio;
                if ((newFrame.origin.x - horizontalFactoredDisance) < targetOrigin.x) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.x - horizontalFactoredDisance) > originalOrigin.x) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.x -= horizontalFactoredDisance;
                }
                break;
            }
            case STKLayoutPositionRight: {
                targetOrigin.x += kBandingAllowance * _distanceRatio;
                if ((newFrame.origin.x + horizontalFactoredDisance) > targetOrigin.x) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.x + horizontalFactoredDisance) < originalOrigin.x) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.x += horizontalFactoredDisance;
                }
                break;
            }
        }
        iconView.frame = newFrame;
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
        CGFloat translatedDistance = distance * (idx + 1) * _distanceRatio;
        
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionLeft distanceFromCentre:idx + 1];
        targetOrigin.x -= kBandingAllowance * _distanceRatio;

        
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
        CGFloat translatedDistance = distance * (idx + 1) * _distanceRatio;
        
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionRight distanceFromCentre:idx + 1];
        targetOrigin.x += kBandingAllowance * _distanceRatio;
        
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

- (CGPoint)_getDisplacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position
{
    // Calculate the positions manually, as -[SBIconListView originForIconAtX:Y:] only gives coordinates that will be on screen, but allow for off-screen icons too.
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];
    SBIconView *iconView = [self _getIconViewForIcon:icon];
    
    CGPoint originalOrigin = [listView originForIcon:icon]; // Use the original location as a reference, as the iconview might have been displaced.
    CGRect originalFrame = (CGRect){{originalOrigin.x, originalOrigin.y}, {iconView.frame.size.width, iconView.frame.size.height}};
    
    CGPoint returnPoint;
    NSArray *currentArray = [self _appearingIconsForPosition:position];
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

- (CGFloat)_distanceFromCentre:(CGPoint)point
{
    SBIconView *iconView = [self _getIconViewForIcon:_centralIcon];
    return sqrtf(((point.x - iconView.center.x) * (point.x - iconView.center.x)) + ((point.y - iconView.center.y)  * (point.y - iconView.center.y))); // distance formula
}


- (void)_makeAllIconsPerformBlock:(void(^)(SBIcon *))block
{
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

- (void)_calculateDistanceRatio
{
    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    CGPoint referencePoint = [listView originForIconAtX:2 Y:2];
    CGPoint verticalOrigin = [listView originForIconAtX:2 Y:1];
    CGPoint horizontalOrigin = [listView originForIconAtX:1 Y:2];

    CGFloat verticalDistance = referencePoint.y - verticalOrigin.y;
    CGFloat horizontalDistance = referencePoint.x - horizontalOrigin.x;

    _distanceRatio = (horizontalDistance / verticalDistance);
}

- (void)_findIconsWithOffScreenTargets
{
    [_offScreenIconsLayout release];
    _offScreenIconsLayout = [[STKIconLayout alloc] init]; 

    [_disappearingIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        CGRect listViewBounds = STKListViewForIcon(_centralIcon).bounds;

        CGPoint target = [self _getDisplacedOriginForIcon:icon withPosition:position];
        CGRect genericFrame = [self _getIconViewForIcon:_centralIcon].frame;

        CGRect targetRect = (CGRect) {{target.x, target.y}, {genericFrame.size.width, genericFrame.size.height}}; // Create the icon's target rect using width and height from the central icon view.

        switch (position) {
            case STKLayoutPositionTop: {
                if (CGRectGetMaxY(targetRect) <= (listViewBounds.origin.y + 20)) {
                    // Add 20 to account for status bar frame
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }

            case STKLayoutPositionBottom: {
                if (CGRectGetMidY(targetRect) >= CGRectGetHeight(listViewBounds)) {
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }

            case STKLayoutPositionLeft: {
                if (CGRectGetMaxX(targetRect) <= listViewBounds.origin.y) {
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }

            case STKLayoutPositionRight: {
                if (CGRectGetMinX(targetRect) >= CGRectGetWidth(listViewBounds)) {
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }
        }
    }];
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

- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral
{
    [[objc_getClass("SBIconController") sharedInstance] setCurrentPageIconsPartialGhostly:alpha forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];
    for (SBIcon *icon in _offScreenIconsLayout.bottomIcons) {
        [self _getIconViewForIcon:icon].alpha = alpha;
    }
}

- (void)_setAlphaForAppearingLabelsAndShadows:(CGFloat)alpha
{
    for (NSArray *iconViews in [[_iconViewsTable objectEnumerator] allObjects]) {
        for (SBIconView *iconView in iconViews) {
            ((UIImageView *)[iconView valueForKey:@"_shadow"]).alpha = alpha;
            [iconView setIconLabelAlpha:alpha];
        }
    }
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
    [[objc_getClass("SBIconController") sharedInstance] setPageControlAlpha:alpha];
}

#pragma mark - SBIconViewDelegate
- (void)iconTapped:(SBIconView *)iconView
{
    [iconView setHighlighted:YES delayUnhighlight:YES];
    if (_interactionHandler) {
        _interactionHandler(iconView);
    }
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
