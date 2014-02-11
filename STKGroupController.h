#import "STKGroupView.h"

@interface STKGroupController : NSObject <STKGroupViewDelegate, UIGestureRecognizerDelegate>

+ (instancetype)sharedController;

@property (nonatomic, readonly) STKGroupView *openGroupView;

- (void)addGroupViewToIconView:(SBIconView *)iconView;
- (void)removeGroupViewFromIconView:(SBIconView *)iconView;

@end
