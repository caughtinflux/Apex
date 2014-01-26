#import "STKGroupController.h"
#import "STKConstants.h"

@implementation STKGroupController

+ (instancetype)sharedController
{
	static dispatch_once_t pred;
	static id _si;
	dispatch_once(&pred, ^{
		_si = [[self alloc] init];
	});
	return _si;
}

- (void)addGroupViewToIconView:(SBIconView *)iconView
{
    if ([iconView groupView]) {
        [iconView removeGroupView];
    }
    STKGroup *group = [[STKPreferences preferences] groupForIcon:iconView.icon];
    group.lastKnownCoordinate = [STKGroupLayoutHandler coordinateForIcon:group.centralIcon];
    if (!group) {
    	group = [self _groupWithEmptySlotsForIconView:iconView];
    }
    STKGroupView *groupView = [[[STKGroupView alloc] initWithGroup:group] autorelease];
    groupView.delegate = self;
    [iconView setGroupView:groupView];
}

- (void)removeGroupViewFromIconView:(SBIconView *)iconView
{
    [iconView removeGroupView];
}

- (STKGroup *)_groupWithEmptySlotsForIconView:(SBIconView *)iconView
{
	STKGroupLayout *slotLayout = [STKGroupLayoutHandler emptyLayoutForIconAtLocation:[STKGroupLayoutHandler locationForIconView:iconView]];
	STKGroup *group = [[STKGroup alloc] initWithCentralIcon:iconView.icon layout:slotLayout];
    group.empty = YES;
	return [group autorelease];
}

#pragma mark - Group View Delegate
- (BOOL)groupViewShouldOpen:(STKGroupView *)groupView
{
    return YES;
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return YES;   
}

- (void)iconTapped:(SBIconView *)iconView
{
    [iconView.icon launchFromLocation:SBIconLocationHomeScreen];
}

- (BOOL)iconViewDisplaysCloseBox:(SBIconView *)iconView
{
    return NO;
}

- (BOOL)iconViewDisplaysBadges:(SBIconView *)iconView
{
    return [[CLASS(SBIconController) sharedInstance] iconViewDisplaysBadges:iconView];
}

- (BOOL)icon:(SBIconView *)iconView canReceiveGrabbedIcon:(SBIcon *)grabbedIcon
{
    return NO;
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    if ([iconView.icon isEmptyPlaceholder]) {
        return;
    }
}

@end
