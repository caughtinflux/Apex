#import "STKConstants.h"

%hook SBLeafIcon

- (id)badgeNumberOrString
{
    NSNumber *ret = %orig();
    STKGroup *group = [[STKPreferences sharedPreferences] groupForCentralIcon:self];
    if (!group || ![STKPreferences sharedPreferences].shouldShowSummedBadges || [[CLASS(SBUIController) sharedInstance] isAppSwitcherShowing]) {
        return ret;
    }
    ret = ret ?: @0;
    if ([ret isKindOfClass:[NSNumber class]]) {
        NSInteger subAppTotal = 0;
        for (SBIcon *icon in [[STKPreferences sharedPreferences] groupForCentralIcon:self].layout) {
            subAppTotal += [icon badgeValue];
        }
        ret = @([ret integerValue] + subAppTotal);
        if ([ret integerValue] <= 0) {
            ret = nil;
        }

    }
    return ret;
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

%ctor
{
    @autoreleasepool {
        %init();
    }   
}
