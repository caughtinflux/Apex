#import "STKConstants.h"

@interface STKGroupController : NSObject

+ (instancetype)sharedController;

- (void)addGroupViewToIconView:(SBIconView *)iconView;
- (void)removeGroupViewFromIconView:(SBIconView *)iconView;;

@end
