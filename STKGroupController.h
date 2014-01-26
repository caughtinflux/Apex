#import "STKGroupView.h"

@interface STKGroupController : NSObject <STKGroupViewDelegate>

+ (instancetype)sharedController;

- (void)addGroupViewToIconView:(SBIconView *)iconView;
- (void)removeGroupViewFromIconView:(SBIconView *)iconView;

@end
