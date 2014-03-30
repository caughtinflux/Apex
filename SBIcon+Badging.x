#import "STKConstants.h"

%hook SBLeafIcon

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

- (NSInteger)accessoryTypeForLocation:(SBIconLocation)location
{
    if ([self badgeNumberOrString]) {
        return 1;
    }
    return %orig();
}

- (NSString *)accessoryTextForLocation:(SBIconLocation)location
{
    NSString *text = %orig();
    if ([STKGroupController sharedController].openGroupView.group.centralIcon == self
        || ![STKPreferences sharedPreferences].shouldShowSummedBadges) {
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

- (void)noteBadgeDidChange
{
    %orig();
    STKGroup *group = [[STKPreferences sharedPreferences] groupForSubappIcon:self];
    if (group) {
        [group.centralIcon noteBadgeDidChange];
    }
}

%end 

%ctor
{
    @autoreleasepool {
        %init();
    }   
}
