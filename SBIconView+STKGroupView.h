#import <SpringBoard/SpringBoard.h>

@class STKGroupView;
@interface SBIconView (STKGroupView)
- (void)setGroupView:(STKGroupView *)view;
- (void)removeGroupView;
- (STKGroupView *)groupView;

@end
