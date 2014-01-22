#import "STKGroupController.h"

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
    if (!group) {
    	group = [self _groupWithEmptySlotsForIconView:iconView];
    }
    STKGroupView *groupView = [[[STKGroupView alloc] initWithGroup:group] autorelease];
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

@end
