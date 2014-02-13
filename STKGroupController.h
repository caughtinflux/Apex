#import "STKGroupView.h"
#import "STKSelectionView.h"

@interface STKGroupController : NSObject <STKGroupViewDelegate, UIGestureRecognizerDelegate, STKSelectionViewDelegate>

+ (instancetype)sharedController;

@property (nonatomic, readonly) STKGroupView *openGroupView;

- (void)addGroupViewToIconView:(SBIconView *)iconView;
- (void)removeGroupViewFromIconView:(SBIconView *)iconView;

@end
