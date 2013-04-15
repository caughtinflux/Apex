#import "STKStackManager.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"

#import <objc/runtime.h>

#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIcon.h>
#import <SpringBoard/SBApplicationIcon.h>
#import <SpringBoard/SBIconModel.h>
#import <SpringBoard/SBIconViewMap.h>
#import <SpringBoard/SBIconView.h>
#import <SpringBoard/SBIconListView.h>
#import <SpringBoard/SBDockIconListView.h>

static NSString * const STKStackTopIconsKey    = @"topicons";
static NSString * const STKStackBottomIconsKey = @"bottomicons";
static NSString * const STKStackLeftIconsKey   = @"lefticons";
static NSString * const STKStackRightIconsKey  = @"righticons";

#define kEnablingThreshold   55
#define kMaximumDisplacement 80
#define kAnimationDuration   0.2

@interface STKStackManager ()
{
    SBIcon               *_centralIcon;
    STKIconLayout        *_appearingIconsLayout;
    STKIconLayout        *_disappearingIconsLayout;
    STKIconLayoutHandler *_handler;
    NSMapTable           *_iconViewsTable;
    BOOL                  _isExpanded;
    CGFloat               _lastSwipeDistance;
    CGFloat               _currentIconDisplacement;
    STKInteractionHandler _interactionHandler;
}

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance;
- (void)_animateToOpenPosition;
- (void)_animateToClosedPosition;
- (SBIconView *)_getIconViewForIcon:(SBIcon *)icon;
- (NSUInteger)_locationMaskForIcon:(SBIcon *)icon;
- (void)_setAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral disableInteraction:(BOOL)disableInteraction;
- (CGPoint)_getTargetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance;
- (CGFloat)_distanceFromCentre:(CGPoint)centre;

@end

@implementation STKStackManager
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons interactionHandler:(STKInteractionHandler)handler
{
    if ((self = [super init])) {
        _centralIcon             = [centralIcon retain];
        _handler                 = [[STKIconLayoutHandler alloc] init];
        _interactionHandler      = [handler copy];
        _appearingIconsLayout    = [[_handler layoutForIcons:icons aroundIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
        _disappearingIconsLayout = [[_handler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconsLayout] retain];
        _iconViewsTable          = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory capacity:4];

        CLog(@"_appearingIconsLayout t: %@ b: %@ l: %@ r:%@", _appearingIconsLayout.topIcons, _appearingIconsLayout.bottomIcons, _appearingIconsLayout.leftIcons, _appearingIconsLayout.rightIcons);
        CLog(@"_disappearingIconsLayout t: %@ b: %@ l: %@ r:%@", _disappearingIconsLayout.topIcons, _disappearingIconsLayout.bottomIcons, _disappearingIconsLayout.leftIcons, _disappearingIconsLayout.rightIcons);
    }
    return self;
}

- (void)dealloc
{
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

- (void)setupView
{
    [_appearingIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
        SBIconView *iconView = [[[objc_getClass("SBIconView") alloc] initWithDefaultSize] autorelease];
        [iconView setIcon:icon];
        [iconView setDelegate:self];
        SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];

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
}

- (void)touchesDraggedForDistance:(CGFloat)distance
{
    if (distance > 0 && _currentIconDisplacement >= kMaximumDisplacement) {
        return;
    }
    else if (distance < 0 && _currentIconDisplacement <= 0) {
        // if -ve
        return;
    }
    distance *= 0.1; // factor this shit daooooon    
    [self _moveAllIconsInRespectiveDirectionsByDistance:distance];
    
    _lastSwipeDistance = distance;
    _currentIconDisplacement += distance;

    CLog(@"last swipe distance: %f", _lastSwipeDistance);
    CLog(@"_currentIconDisplacement: %f", _currentIconDisplacement);
}

- (void)touchesEnded
{
    if (_currentIconDisplacement >= kEnablingThreshold) {
        [self _setAlphaForAllIcons:0.4f excludingCentralIcon:YES disableInteraction:YES]; // Set the alpha before animating to open position, as _animate to open position sets the disappearing icons' alphas to 0
        [self _animateToOpenPosition];
    }
    else {
        [self closeStack];
        [self _setAlphaForAllIcons:1.0f excludingCentralIcon:YES disableInteraction:NO];
    }
}
 
- (void)closeStack
{
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];
    [self _animateToClosedPosition];
    [listView setIconsNeedLayout];
    [listView layoutIconsIfNeeded:kAnimationDuration domino:YES];
    for (SBIcon *icon in [listView icons]) {
        [[self _getIconViewForIcon:icon] setAlpha:1.0];
    }
}

#pragma mark - Private Methods
- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance
{
    // Move icons currently on display to make way for stack icons
    [_disappearingIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
        SBIconView *iconView = [self _getIconViewForIcon:icon];
        CGRect newFrame = iconView.frame;
        switch (position) {
            case STKLayoutPositionTop: {
                newFrame.origin.y -= distance;
                break;
            }
            case STKLayoutPositionBottom: {
                newFrame.origin.y += distance;
                break;
            }
            case STKLayoutPositionLeft: {
                newFrame.origin.x -= distance;
                break;
            }
            case STKLayoutPositionRight: {
                newFrame.origin.x += distance;
                break;
            }
        }
        iconView.frame = newFrame;
    }];

    // Move stack icons
    [(NSArray *)[_iconViewsTable objectForKey:STKStackTopIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionTop distanceFromCentre:idx + 1];
        iconView.alpha = 1.f;
        if (((newFrame.origin.y - distance) > targetOrigin.y) && (!((newFrame.origin.y - distance) > [self _getIconViewForIcon:_centralIcon].frame.origin.y))) {
            newFrame.origin.y -= distance;
        }
        iconView.frame = newFrame;
    }];

    [(NSArray *)[_iconViewsTable objectForKey:STKStackBottomIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionBottom distanceFromCentre:idx + 1];
        iconView.alpha = 1.f;
        if ((newFrame.origin.y + distance) < targetOrigin.y && (!((newFrame.origin.y + distance) < [self _getIconViewForIcon:_centralIcon].frame.origin.y))) {
            newFrame.origin.y += distance;
        }
        iconView.frame = newFrame;
    }];

    [(NSArray *)[_iconViewsTable objectForKey:STKStackLeftIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionLeft distanceFromCentre:idx + 1];
        iconView.alpha = 1.f;
        if (((newFrame.origin.x - distance) > targetOrigin.x) && (!((newFrame.origin.x - distance) > [self _getIconViewForIcon:_centralIcon].frame.origin.x))) {
            newFrame.origin.x -= distance;
        }
        iconView.frame = newFrame;
    }];

    [(NSArray *)[_iconViewsTable objectForKey:STKStackRightIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _getTargetOriginForIconAtPosition:STKLayoutPositionRight distanceFromCentre:idx + 1];
        iconView.alpha = 1.f;
        if (((newFrame.origin.x + distance) < targetOrigin.x) && (!((newFrame.origin.x + distance) < [self _getIconViewForIcon:_centralIcon].frame.origin.x))) {
            newFrame.origin.x += distance;
        }
        iconView.frame = newFrame;
    }];
}

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

        [_disappearingIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
            [self _getIconViewForIcon:icon].alpha = 0;
        }];
    } completion:^(BOOL finished) {
        if (finished) {
            _isExpanded = YES;
        }
    }];
}

- (void)_animateToClosedPosition
{
    [UIView animateWithDuration:kAnimationDuration animations:^{
        // Set the frame for all these icons to the frame of their central icon
        for (NSArray *iconViews in [[_iconViewsTable objectEnumerator] allObjects]) {
            for (SBIconView *iconView in iconViews) {
                iconView.frame = [self _getIconViewForIcon:_centralIcon].frame;
                iconView.alpha = 0.f;
            }
        }

        [_disappearingIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
            [self _getIconViewForIcon:icon].alpha = 1;
        }];
    } completion:^(BOOL finished) {
        if (finished) {
            _isExpanded = YES;
        }
    }];
}

- (SBIconView *)_getIconViewForIcon:(SBIcon *)icon
{
    return [[objc_getClass("SBIconViewMap") homescreenMap] iconViewForIcon:icon];
}

- (NSUInteger)_locationMaskForIcon:(SBIcon *)icon
{
    NSUInteger mask = 0x0;
    
    if (!icon) {
        return mask;
    }

    STKIconLayoutHandler *handler = [[STKIconLayoutHandler alloc] init];
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];
    STKIconCoordinates *coordinates = [handler copyCoordinatesForIcon:icon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    [handler release];

    DLog(@"coordinates: x = %i y = %i index = %i", coordinates->xPos, coordinates->yPos, coordinates->index);
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

- (void)_setAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)shouldExcludeCentral disableInteraction:(BOOL)disableInteraction
{
    for (SBIcon *icon in [[objc_getClass("SBIconController") sharedInstance] currentRootIconList].icons) {
        if (shouldExcludeCentral && [icon.leafIdentifier isEqualToString:_centralIcon.leafIdentifier]) {
            // don't touch the icon if it is the central icon
            continue;
        }
        SBIconView *iconView = [self _getIconViewForIcon:icon];
        iconView.alpha = alpha;
        iconView.userInteractionEnabled = !disableInteraction;
    }
}

- (CGFloat)_distanceFromCentre:(CGPoint)point
{
    SBIconView *iconView = [self _getIconViewForIcon:_centralIcon];
    return sqrtf(((point.x - iconView.center.x) * (point.x - iconView.center.x)) + ((point.y - iconView.center.y)  * (point.y - iconView.center.y))); // distance formula
}

#pragma mark - SBIconViewDelegate
- (void)iconTapped:(SBIconView *)iconView
{
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
