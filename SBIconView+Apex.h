#import <SpringBoard/SpringBoard.h>

@class STKGroupView;
@interface SBIconView (Apex)
- (void)setGroupView:(STKGroupView *)view;
- (void)removeGroupView;
- (STKGroupView *)groupView;

@end
