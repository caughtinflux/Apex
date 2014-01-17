#import "STKGroupController.h"

@implementation STKGroupController

- (void)addGroupViewToIconView:(SBIconView *)iconView
{
    if ([iconView groupView]) {
        [iconView removeGroupView];
    }
    STKGroup *group = [[STKPreferences preferences] groupForIcon:iconView.icon];
    STKGroupView *groupView = [[[STKGroupView alloc] initWithGroup:group] autorelease];
    [iconView setGroupView:groupView];
    [groupView configureSuperview];
}

- (void)removeGroupViewFromIconView:(SBIconView *)iconView
{
    [iconView removeGroupView];
}

@end
