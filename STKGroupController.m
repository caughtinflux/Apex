#import "STKGroupController.h"
#import "STKConstants.h"

@implementation STKGroupController
{
    STKGroupView *_openGroupView;
    BOOL _openGroupIsEditing;
}

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
    iconView.groupView = nil;
}

- (STKGroup *)_groupWithEmptySlotsForIconView:(SBIconView *)iconView
{
	STKGroupLayout *slotLayout = [STKGroupLayoutHandler emptyLayoutForIconAtLocation:[STKGroupLayoutHandler locationForIconView:iconView]];
	STKGroup *group = [[STKGroup alloc] initWithCentralIcon:iconView.icon layout:slotLayout];
    group.empty = YES;
	return [group autorelease];
}

- (UIScrollView *)_currentScrollView
{
    SBFolderController *currentFolderController = [[CLASS(SBIconController) sharedInstance] _currentFolderController];
    return [currentFolderController.contentView scrollView];
}

#pragma mark - Group View Delegate
- (BOOL)shouldGroupViewOpen:(STKGroupView *)groupView
{
    return YES;
}

- (void)groupViewWillOpen:(STKGroupView *)groupView
{
    if (groupView.activationMode != STKActivationModeDoubleTap) {
        [self _currentScrollView].scrollEnabled = NO;
    }
}

- (void)groupViewDidOpen:(STKGroupView *)groupView
{
    _openGroupView = groupView;
}

- (void)groupViewWillClose:(STKGroupView *)groupView
{
    [self _currentScrollView].scrollEnabled = YES;
}

- (void)groupViewDidClose:(STKGroupView *)groupView
{
    if (_openGroupIsEditing) {
        for (SBIconView *iconView in _openGroupView.subappLayout) {
            [iconView removeApexOverlay];
        }
    }
    _openGroupView = nil;
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return YES;   
}

- (void)iconTapped:(SBIconView *)iconView
{
    if (_openGroupIsEditing) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [iconView setHighlighted:NO];
    });
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
    if ([iconView.icon isEmptyPlaceholder] || _openGroupView == nil) {
        return;
    }
    [iconView setHighlighted:NO];
    for (SBIconView *iconView in _openGroupView.subappLayout) {
        [iconView showApexOverlayOfType:STKOverlayTypeEditing];
    }
    _openGroupIsEditing = YES;
}

- (void)iconTouchBegan:(SBIconView *)iconView
{
    [iconView setHighlighted:YES];   
}

- (void)icon:(SBIconView *)iconView touchEnded:(BOOL)ended
{
    [iconView setHighlighted:NO];
}

@end
