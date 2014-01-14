#import "STKPreferences.h"

static NSString * const ActivationModeKey   = @"STKActivationMode";
static NSString * const ShowPreviewKey      = @"STKShowPreview";
static NSString * const GroupStateKey       = @"STKGroupState";
static NSString * const ClosesOnLaunchKey   = @"STKStackClosesOnLaunch";
static NSString * const LockLayoutsKey      = @"STKLockLayouts";
static NSString * const ShowSummedBadgesKey = @"STKShowSummedBadges";
static NSString * const CentralIconKey      = @"STKCentralIcon";

#define GETBOOL(_key, _default) (_preferences[_key] ? [_preferences[_key] boolValue] : _default)

@implementation STKPreferences
{
    NSMutableDictionary *_preferences;
    NSMutableDictionary *_groupState;
    NSMutableDictionary *_groups;
}

+ (instancetype)preferences
{
    static dispatch_once_t pred;
    static STKPreferences *_sharedInstance;
    dispatch_once(&pred, ^{
        _sharedInstance = [[self alloc] init];
        [_sharedInstance reloadPreferences];
    });
    return _sharedInstance;
}

- (void)reloadPreferences
{
    [_preferences release];
    _preferences = [[NSMutableDictionary alloc] initWithContentsOfFile:kPrefPath];
    NSDictionary *iconState = _preferences[GroupStateKey];
    for (NSString *iconID in [iconState allKeys]) {
        @autoreleasepool {
            NSDictionary *groupRepr = iconState[iconID];
            STKGroup *group = [[[STKGroup alloc] initWithDictionary:groupRepr] autorelease];
            [self addGroup:group];
        }
    }
}

- (void)_synchronize
{
    NSDictionary *groupState = [self _groupStateFromGroups];
    _preferences[GroupStateKey] = groupState;
    [_preferences writeToFile:kPrefPath atomically:YES];
}

- (void)addGroup:(STKGroup *)group
{
    if (!_groups) {
        _groups = [NSMutableDictionary new];
    }
    _groups[group.centralIcon.leafIdentifier] = group;
}

- (void)removeGroup:(STKGroup *)group
{
    [_groups removeObjectForKey:group.centralIcon.leafIdentifier];
}

- (STKGroup *)groupForCentralIcon:(SBIcon *)icon
{
    return _groups[icon.leafIdentifier];
}

- (NSDictionary *)_groupStateFromGroups
{
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    for (STKGroup *group in _groups) {
        state[group.centralIcon.leafIdentifier] = [group dictionaryRepresentation];
    }
    return state;
}

@end
