#import "STKConstants.h"

%hook SBLeafIcon

- (id)badgeNumberOrString
{
    SBIconController *iconController = [CLASS(SBIconController) sharedInstance];
    NSNumber *topBadge = %orig();
    STKGroup *group = [[STKPreferences sharedPreferences] groupForCentralIcon:self];
    if (!group || ![STKPreferences sharedPreferences].shouldShowSummedBadges || [[CLASS(SBUIController) sharedInstance] isAppSwitcherShowing]) {
        return topBadge;
    }
    if (![iconController iconAllowsBadging:self] || !topBadge) {
        topBadge = @0;
    }
    if ([topBadge isKindOfClass:[NSNumber class]]) {
        NSInteger subAppTotal = 0;
        for (SBIcon *icon in [[STKPreferences sharedPreferences] groupForCentralIcon:self].layout) {
            subAppTotal += ([iconController iconAllowsBadging:icon] ? [icon badgeValue] : 0);
        }
        topBadge = @([topBadge integerValue] + subAppTotal);
        if ([topBadge integerValue] <= 0) {
            topBadge = nil;
        }
    }
    return topBadge;
}

- (NSInteger)accessoryTypeForLocation:(SBIconLocation)location
{
    if (![[%c(SBUIController) sharedInstance] isAppSwitcherShowing] && [self badgeNumberOrString]) {
        return 1;
    }
    return %orig();
}

- (NSString *)accessoryTextForLocation:(SBIconLocation)location
{
    NSString *text = %orig();
    if ([STKGroupController sharedController].openingGroupView.group.centralIcon == self
        || ![STKPreferences sharedPreferences].shouldShowSummedBadges
        || [[%c(SBUIController) sharedInstance] isAppSwitcherShowing]) {
        return text;
    }
    else {
        id badgeNumberOrString = [self badgeNumberOrString];
        if ([badgeNumberOrString isKindOfClass:[NSNumber class]] && [badgeNumberOrString integerValue] > 0) {
            text = [badgeNumberOrString stringValue];
        }
    }
    return text;
}

- (void)setBadge:(id)badge
{
    %orig();
    [self noteBadgeDidChange];
}

- (void)noteBadgeDidChange
{
    %orig();
    STKGroup *group = [[STKPreferences sharedPreferences] groupForSubappIcon:self];
    [group.centralIcon noteBadgeDidChange];
}

%end

%hook SBApplication
- (void)setBadge:(id)badge
{
    %orig();
    SBIconModel *iconModel = (SBIconModel *)[[CLASS(SBIconController) sharedInstance] model];
    SBApplicationIcon *icon = [iconModel applicationIconForDisplayIdentifier:self.displayIdentifier];
    [icon noteBadgeDidChange];
}
%end

%ctor
{
    @autoreleasepool {
        %init();
    }   
}
