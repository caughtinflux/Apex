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

static NSString * const STKStackTopIconsKey = @"topicons";
static NSString * const STKStackBottomIconsKey = @"bottomicons";
static NSString * const STKStackLeftIconsKey = @"lefticons";
static NSString * const STKStackRightIconsKey = @"righticons";

#define kMinimumSwipeDistance 65
#define kMaximumSwipeDistance 135

@interface STKStackManager ()
{
    SBIcon               *_centralIcon;
    STKIconLayout        *_appearingIconsLayout;
    STKIconLayout        *_disappearingIconsLayout;
    STKIconLayoutHandler *_handler;
    NSMapTable           *_iconViewsTable;
    CGFloat              *_currentSwipeDistance;
}
- (SBIconView *)_getIconViewForIcon:(SBIcon *)icon;
- (NSUInteger)_locationMaskForIcon:(SBIcon *)icon;
- (CGPoint)_getTargetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance;
@end

@implementation STKStackManager
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons
{
    if ((self = [super init])) {
        _centralIcon             = [centralIcon retain];
        _handler                 = [[STKIconLayoutHandler alloc] init];
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
    [_handler release];
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
    // [self _moveAllIconsInRespectiveDirectionsByDistance:distance];
}

- (void)touchesEnded
{

}

- (void)closeStack
{

}

#pragma mark - Private Methods
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

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance
{
}

@end
