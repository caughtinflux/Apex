#import "STKGroupView.h"

@interface STKGroupController : NSObject <STKGroupViewDelegate>

+ (instancetype)sharedController;

@property (nonatomic, readonly) STKGroupView *openGroupView;

- (void)addGroupViewToIconView:(SBIconView *)iconView;
- (void)removeGroupViewFromIconView:(SBIconView *)iconView;

@end
