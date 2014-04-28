#import "STKGroupView.h"
#import "STKSelectionView.h"

typedef NS_ENUM(NSUInteger, STKClosingEvent) {
	STKClosingEventHomeButtonPress = 1,
	STKClosingEventListViewScroll,
	STKClosingEventSwitcherActivation,
	STKClosingEventLock,
};


@interface STKGroupController : NSObject <STKGroupViewDelegate, UIGestureRecognizerDelegate>

+ (instancetype)sharedController;

@property (nonatomic, readonly) STKGroupView *openGroupView;
@property (nonatomic, readonly) STKGroupView *openingGroupView;

- (void)addOrUpdateGroupViewForIconView:(SBIconView *)iconView;
- (void)removeGroupViewFromIconView:(SBIconView *)iconView;

- (void)performRotationWithDuration:(NSTimeInterval)duration;

// returns YES if we reacted to the event, NO if ignored
- (BOOL)handleClosingEvent:(STKClosingEvent)event;

- (void)handleIconRemoval:(SBIcon *)removedIcon;

@end
