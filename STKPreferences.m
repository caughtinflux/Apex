#import "STKPreferences.h"
#import <notify.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-const-variable"
static NSString * const ActivationModeKey   = @"activationMode";
static NSString * const ShowPreviewKey      = @"preview";
static NSString * const GroupStateKey       = @"state";
static NSString * const ClosesOnLaunchKey   = @"closeOnLaunch";
static NSString * const LockLayoutsKey      = @"lockLayouts";
static NSString * const ShowSummedBadgesKey = @"summedBadges";
static NSString * const CentralIconKey      = @"centralIcon";
#pragma clang diagnostic pop

#define GETBOOL(_key, _default) (_preferences[_key] ? [_preferences[_key] boolValue] : _default)

@implementation STKPreferences
{
    NSMutableDictionary *_preferences;
    NSMutableDictionary *_groups;
    NSMutableDictionary *_subappToCentralMap;

    STKActivationMode _activationMode;
    BOOL _shouldLockLayouts;
    BOOL _shouldShowPreviews;
}

+ (instancetype)sharedPreferences
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
    [_groups release];
    [_subappToCentralMap release];
    _subappToCentralMap = nil;
    _groups = nil;

    _preferences = [[NSMutableDictionary alloc] initWithContentsOfFile:kPrefPath] ?: [NSMutableDictionary new];
    NSDictionary *iconState = _preferences[GroupStateKey];
    NSMutableArray *groupArray = [NSMutableArray array];
    for (NSString *iconID in [iconState allKeys]) {
        @autoreleasepool {
            NSDictionary *groupRepr = iconState[iconID];
            STKGroup *group = [[[STKGroup alloc] initWithDictionary:groupRepr] autorelease];
            if (group.centralIcon) {
                [groupArray addObject:group];
                [group addObserver:self];
            }
        }
    }
    [self _addOrUpdateGroups:groupArray];
}

- (NSArray *)identifiersForSubappIcons
{
    return [_subappToCentralMap allKeys];
}

- (void)addOrUpdateGroup:(STKGroup *)group
{
    if (!group.centralIcon.leafIdentifier) {
        return;
    }
    if (!_groups) {
        _groups = [NSMutableDictionary new];
    }
    if (group.state == STKGroupStateEmpty) {
        [_groups removeObjectForKey:group.centralIcon.leafIdentifier];
    }
    else {
        _groups[group.centralIcon.leafIdentifier] = group;
    }
    [self _resetSubappMap];
    [self _synchronize];
}

- (void)removeGroup:(STKGroup *)group
{
    [_groups removeObjectForKey:group.centralIcon.leafIdentifier];
    [self _synchronize];
}

- (STKGroup *)groupForCentralIcon:(SBIcon *)icon
{
    return _groups[icon.leafIdentifier];
}

- (STKGroup *)groupForSubappIcon:(SBIcon *)icon
{
    return _groups[_subappToCentralMap[icon.leafIdentifier]];
}

- (void)_synchronize
{
    NSDictionary *groupState = [self _groupStateFromGroups];
    _preferences[GroupStateKey] = groupState;

    NSOutputStream *outputStream = [NSOutputStream outputStreamToFileAtPath:kPrefPath append:NO];
    [outputStream open];
    NSError *err = nil;
    NSInteger bytesWritten = [NSPropertyListSerialization writePropertyList:_preferences
                                                                   toStream:outputStream
                                                                     format:NSPropertyListBinaryFormat_v1_0
                                                                    options:0
                                                                      error:&err];
    if (bytesWritten > 0) {
        DLog(@"Wrote %zd bytes to file", bytesWritten);
    }
    else {
        DLog(@"Failed to write to stream. Error %zd: %@", err.code, err.localizedDescription);
    }
}

- (void)_addOrUpdateGroups:(NSArray *)groupArray
{
    if (!_groups) {
        _groups = [NSMutableDictionary new];
    }
    for (STKGroup *group in groupArray) {
        _groups[group.centralIcon.leafIdentifier] = group;
        [self _mapSubappsInGroup:group];
    }
    [self _synchronize];   
}

- (void)_resetSubappMap
{
    [_subappToCentralMap release];
    _subappToCentralMap = [NSMutableDictionary new];
    for (STKGroup *group in [_groups allValues]) {
        [self _mapSubappsInGroup:group];
    }
}

- (void)_mapSubappsInGroup:(STKGroup *)group
{
    if (!_subappToCentralMap) {
        _subappToCentralMap = [NSMutableDictionary new];
    }
    for (SBIcon *icon in group.layout) {
        if ([icon isLeafIcon]) {
            _subappToCentralMap[icon.leafIdentifier] = group.centralIcon.leafIdentifier;
        }
    }
}

- (void)_validateGroups
{

}

- (NSDictionary *)_groupStateFromGroups
{
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    for (STKGroup *group in [_groups allValues]) {
        state[group.centralIcon.leafIdentifier] = [group dictionaryRepresentation];
    }
    return state;
}

#pragma mark - STKGroupObserver
- (void)groupDidFinalizeState:(STKGroup *)group
{
    for (SBIcon *subappIcon in group.layout) {
        STKGroup *previousGroup = [self groupForSubappIcon:subappIcon];
        if (previousGroup && group != previousGroup) {
            // Another group has `subappIcon`, so remove subappIcon from it
            STKGroupSlot slotForRemovedIcon = [previousGroup.layout slotForIcon:subappIcon];
            [previousGroup replaceIconInSlot:slotForRemovedIcon withIcon:nil];
            [previousGroup forceRelayout];
            [self addOrUpdateGroup:previousGroup];
        }
    }
    [self addOrUpdateGroup:group];
}

- (void)groupDidRelayout:(STKGroup *)group
{
    [self addOrUpdateGroup:group];
    notify_post("com.a3tweaks.apex.iconstatechanged");
}

@end
