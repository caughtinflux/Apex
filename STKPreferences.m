#import "STKPreferences.h"
#import <notify.h>

static NSString * const ActivationModeKey   = @"activationMode";
static NSString * const ShowPreviewKey      = @"previewEnabled";
static NSString * const GroupStateKey       = @"state";
static NSString * const ClosesOnLaunchKey   = @"closeOnLaunch";
static NSString * const LockLayoutsKey      = @"lockLayouts";
static NSString * const ShowSummedBadgesKey = @"summedBadges";
static NSString * const UserWelcomedKey     = @"welcomed";

#define GETBOOL(_key, _default) (_preferences[_key] ? [_preferences[_key] boolValue] : _default)

@interface STKPreferences ()
{
    NSMutableDictionary *_preferences;
    NSMutableDictionary *_groups;
    NSMutableDictionary *_subappToCentralMap;
}

static void STKPrefsChanged (
   CFNotificationCenterRef center,
   void *observer,
   CFStringRef name,
   const void *object,
   CFDictionaryRef userInfo
);

@end

@implementation STKPreferences

+ (instancetype)sharedPreferences
{
    static dispatch_once_t pred;
    static STKPreferences *_sharedInstance;
    dispatch_once(&pred, ^{
        _sharedInstance = [[self alloc] init];
        [_sharedInstance reloadPreferences];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                        NULL, 
                                        (CFNotificationCallback)STKPrefsChanged, 
                                        STKPrefsChangedNotificationName, 
                                        NULL, 
                                        0);
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

- (STKActivationMode)activationMode
{
    return (STKActivationMode)[_preferences[ActivationModeKey] integerValue];
}

- (BOOL)shouldLockLayouts
{
    return GETBOOL(LockLayoutsKey, NO);
}

- (BOOL)shouldShowPreviews
{
    return GETBOOL(ShowPreviewKey, YES);
}

- (BOOL)shouldShowSummedBadges
{
    return GETBOOL(ShowSummedBadgesKey, YES);
}

- (BOOL)shouldCloseOnLaunch
{
    return GETBOOL(ClosesOnLaunchKey, YES);
}

- (BOOL)welcomeAlertShown
{
    return GETBOOL(UserWelcomedKey, NO);
}

- (void)setWelcomeAlertShown:(BOOL)shown
{
    _preferences[UserWelcomedKey] = @(shown);
    [self _synchronize];
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
    @synchronized(self) {
        NSDictionary *groupState = [self _groupStateFromGroups];
        _preferences[GroupStateKey] = groupState;

        // Write atomically.
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingString:@"/com.a3tweaks.Apex.plist"];
        NSOutputStream *outputStream = [NSOutputStream outputStreamToFileAtPath:tempPath append:NO];
        [outputStream open];
        NSError *err = nil;
        [NSPropertyListSerialization writePropertyList:_preferences
                                              toStream:outputStream
                                                format:NSPropertyListBinaryFormat_v1_0
                                               options:0
                                                 error:&err];
        if (err) {
            STKLog(@"Failed to write preferences to to output stream. Error %zd: %@", err.code, err.localizedDescription);
        }
        else {
            NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
            NSURL *prefsURL = [NSURL fileURLWithPath:kPrefPath];
            [[NSFileManager defaultManager] replaceItemAtURL:prefsURL
                                               withItemAtURL:tempURL
                                              backupItemName:@"com.a3tweaks.Apex.last.plist"
                                                     options:NSFileManagerItemReplacementUsingNewMetadataOnly
                                            resultingItemURL:NULL
                                                       error:&err];

            if (err) {
                STKLog(@"Failed to move preferences from temporary to primary path. Error Code %zd: %@", err.code, err.localizedDescription);
                STKLog(@"Trying to save via simple write.");
                BOOL success = [_preferences writeToFile:kPrefPath atomically:YES];
                STKLog(@"%@ writing as plain text", (success ? @"Succeeded" : @"Failed"));
            }
        }
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
    [self _resetSubappMap];
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
    NSMutableArray *groupsToUpdate = [NSMutableArray array];
    for (SBIcon *subappIcon in group.layout) {
        STKGroup *previousGroup = [self groupForSubappIcon:subappIcon];
        if (previousGroup && group != previousGroup) {
            // Another group has `subappIcon`, so remove subappIcon from it
            STKGroupSlot slotForRemovedIcon = [previousGroup.layout slotForIcon:subappIcon];
            [previousGroup replaceIconInSlot:slotForRemovedIcon withIcon:nil];
            [previousGroup forceRelayout];
            [groupsToUpdate addObject:previousGroup];
        }
    }
    [groupsToUpdate addObject:group];
    [self _addOrUpdateGroups:groupsToUpdate];
}

- (void)groupDidRelayout:(STKGroup *)group
{
    [self addOrUpdateGroup:group];
    notify_post("com.a3tweaks.apex.iconstatechanged");
}

static void
STKPrefsChanged (CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    [[STKPreferences sharedPreferences] reloadPreferences];
    [[NSNotificationCenter defaultCenter] postNotificationName:(NSString *)STKPrefsChangedNotificationName object:nil userInfo:nil];
}

@end
