#import "STKConstants.h"

%hook SBIcon

- (id)badgeNumberOrString
{
    NSNumber *ret = %orig() ?: @(0);
    STKGroup *group = [[STKPreferences sharedPreferences] groupForCentralIcon:self];
    if (!group || ![STKPreferences sharedPreferences].shouldShowSummedBadges) {
        return ret;
    }
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

- (void)noteBadgeDidChange
{
    %orig();
    STKGroup *group = [[STKPreferences sharedPreferences] groupForSubappIcon:self];
    if (group) {
        [group.centralIcon noteBadgeDidChange];
    }
}

%end 
