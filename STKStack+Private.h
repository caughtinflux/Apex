#import "STKStack.h"
#import "STKConstants.h"
#import "STKIconLayout.h"

#import <SpringBoard/SpringBoard.h>
#import <QuartzCore/QuartzCore.h>

#ifdef DLog
    #undef DLog
    #define DLog(fmt, ...) NSLog((@"[" kSTKTweakName @"] %@ %s [Line %d] " fmt), _centralIcon.displayName, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif

// Keys to be used for persistence dict
NSString * const STKStackManagerCentralIconKey  = @"STKCentralIcon";
NSString * const STKStackManagerStackIconsKey   = @"STKStackIcons";
NSString * const STKStackManagerCustomLayoutKey = @"STKCustomLayout";

NSString * const STKRecalculateLayoutsNotification = @"STKRecalculate";

#define kMaximumDisplacement kEnablingThreshold + 40
#define kAnimationDuration   0.2
#define kDisabledIconAlpha   0.2
#define kBandingAllowance    ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) ? 25 : 50)
#define kGhostlyRequesterID  1
#define kOverlayDuration     0.12
#define kPopoutDistance      9

#define EQ_COORDS(_a, _b) (_a.xPos == _b.xPos && _a.yPos == _b.yPos)
#define HAS_FE [STKListViewForIcon(_centralIcon) isKindOfClass:objc_getClass("FEIconListView")]

#pragma mark - Private Method Declarations
@interface STKStack ()
/*
*   Icon moving
*/
- (void)_animateToOpenPositionWithDuration:(NSTimeInterval)duration;
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock duration:(NSTimeInterval)duration animateCentralIcon:(BOOL)animateCentralIcon forSwitcher:(BOOL)forSwitcher;

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance performingTask:(void(^)(SBIconView *iv, STKLayoutPosition pos, NSUInteger idx))task;

/*
*   Gesture Recognizing
*/
- (void)_setupGestureRecognizers;
- (void)_handleCloseGesture:(UIGestureRecognizer *)sender; // this is the default action for both swipes
- (void)_cleanupGestureRecognizers;

- (SBIconView *)_iconViewForIcon:(SBIcon *)icon;
- (STKPositionMask)_locationMaskForIcon:(SBIcon *)icon;

- (void)_relayoutRequested:(NSNotification *)notif;

// Returns the target origin for icons in the stack at the moment, in _centralIcon's iconView. To use with the list view, use -[UIView convertPoint:toView:]
- (CGPoint)_targetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance;

// Manually calculates where the displaced icons should go.
- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position usingLayout:(STKIconLayout *)layout;
- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position;

- (void)_calculateDistanceRatio;
- (void)_findIconsToHide;

/*
*   Alpha
*/
// This sexy method disables/enables icon interaction as required.
- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral; 
// Applies `alpha` to the shadow and label of `iconView`
- (void)_setAlpha:(CGFloat)alpha forLabelAndShadowOfIconView:(SBIconView *)iconView;

/*
*   Editing Handling
*/
- (void)_addOverlays;
- (void)_removeOverlays;
- (void)_insertPlaceHolders;
- (void)_removePlaceHolders;


- (void)_addIcon:(SBIcon *)icon atIndex:(NSUInteger)idx position:(STKLayoutPosition)position;

@end
