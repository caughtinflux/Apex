#import "STKGroupView.h"
#import "STKSelectionView.h"

typedef NS_ENUM(NSUInteger, STKClosingEvent) {
	STKClosingEventHomeButtonPress = 1,
	STKClosingEventListViewScroll,
	STKClosingEventLock,
};


@interface STKGroupController : NSObject <STKGroupViewDelegate, UIGestureRecognizerDelegate>

+ (instancetype)sharedController;

@property (nonatomic, readonly) STKGroupView *openGroupView;

- (void)addGroupViewToIconView:(SBIconView *)iconView;
- (void)removeGroupViewFromIconView:(SBIconView *)iconView;

- (void)performRotationWithDuration:(NSTimeInterval)duration;

// returns YES if we reacted to the event, NO if ignored
- (BOOL)handleClosingEvent:(STKClosingEvent)event;

@end
