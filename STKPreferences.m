#import "STKPreferences.h"
#import "STKVersion.h"

#import <notify.h>
#import <MobileGestalt/MobileGestalt.h>
#import <CommonCrypto/CommonDigest.h>
#import <stdio.h>
#import <sys/stat.h>

static NSString * const ShowPreviewKey      = @"previewEnabled";
static NSString * const GroupStateKey       = @"state";
static NSString * const ClosesOnLaunchKey   = @"closeOnLaunch";
static NSString * const ShowSummedBadgesKey = @"summedBadges";
static NSString * const ShowGrabbersKey     = @"showGrabbers";
static NSString * const AllowNewKey         = @"allowNew";
static NSString * const SwipeUpEnabledKey   = @"swipeUpEnabled";
static NSString * const SwipeDownEnabledKey = @"swipeDownEnabled";
static NSString * const DoubleTapEnabledKey = @"doubleTapEnabled";
static NSString * const SwipeToSpotlightKey = @"swipeToSpotlight";
static NSString * const TapToSpotlightKey   = @"tapToSpotlight";
static NSString * const UserWelcomedKey     = @"welcomed";

#define GETBOOL(_key, _default) (_preferences[_key] ? [_preferences[_key] boolValue] : _default)

@interface STKPreferences ()
{
    NSMutableDictionary *_preferences;
    NSMutableDictionary *_groups;
    NSMutableDictionary *_subappToCentralMap;

    STKActivationMode _activationMode;
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
        [_sharedInstance registerDeviceWithAnalytics];
    });
    return _sharedInstance;
}

- (void)reloadPreferences
{
    [_preferences release];
    [_groups release];
    [_subappToCentralMap release];
    _preferences = nil;
    _subappToCentralMap = nil;
    _groups = nil;

    if (IS_8_1()) {
        CFStringRef appID = CFSTR("com.a3tweaks.Apex");
        CFArrayRef keyList = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keyList) {
            _preferences = [(NSDictionary *)CFPreferencesCopyMultiple(keyList, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) mutableCopy];
            CFRelease(keyList);
        }
        if (!_preferences) {
            _preferences = [NSMutableDictionary new];
        }
    }
    else {
        _preferences = [[NSMutableDictionary dictionaryWithContentsOfFile:kPrefPath] mutableCopy] ?: [NSMutableDictionary new];
    }

    NSDictionary *iconState = _preferences[GroupStateKey];
    NSMutableArray *groupArray = [NSMutableArray array];
    for (NSString *iconID in [iconState allKeys]) {
        @autoreleasepool {
            NSDictionary *groupRepr = iconState[iconID];
            STKGroup *group = [[[STKGroup alloc] initWithDictionary:groupRepr] autorelease];
            if (group.centralIcon && ([group.layout allIcons].count > 0)) {
                [groupArray addObject:group];
                [group addObserver:self];
            }
        }
    }
    [self _addOrUpdateGroups:groupArray];

    _activationMode = STKActivationModeNone;
    if ([self swipeUpEnabled]) _activationMode |= STKActivationModeSwipeUp;
    if ([self swipeDownEnabled]) _activationMode |= STKActivationModeSwipeDown;
    if ([self doubleTapEnabled]) _activationMode |= STKActivationModeDoubleTap;
}

- (void)registerDeviceWithAnalytics
{
    CFStringRef productType = MGCopyAnswer(kMGProductType);
    CFStringRef OSVersion = MGCopyAnswer(kMGProductVersion);
    CFStringRef UDID = MGCopyAnswer(kMGUniqueDeviceID);
    NSString *URLString = [NSString stringWithFormat:@"http://check.caughtinflux.com/stats/twox/%@/%@/%@/%@", @kPackageVersion, productType, OSVersion, UDID];
    CFRelease(productType); CFRelease(OSVersion); CFRelease(UDID);
    NSURL *URL = [NSURL URLWithString:URLString];
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:URL] queue:nil completionHandler:nil];
}

- (BOOL)swipeUpEnabled
{
    return GETBOOL(SwipeUpEnabledKey, YES);
}

- (BOOL)swipeDownEnabled
{
    return GETBOOL(SwipeDownEnabledKey, YES);
}

- (BOOL)doubleTapEnabled
{
    return GETBOOL(DoubleTapEnabledKey, NO);
}

- (BOOL)shouldLockLayouts
{
    return !(GETBOOL(AllowNewKey, YES));
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

- (BOOL)shouldHideGrabbers
{
    return !(GETBOOL(ShowGrabbersKey, NO));
}

- (BOOL)shouldDisableSearchGesture
{
    return !(GETBOOL(SwipeToSpotlightKey, YES));
}

- (BOOL)shouldOpenSpotlightFromStatusBarTap
{
    return GETBOOL(TapToSpotlightKey, NO);
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
    [self _addOrUpdateGroups:@[group]];
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
    NSString *centralIconIdentifier = _subappToCentralMap[icon.leafIdentifier];
    return _groups[centralIconIdentifier];
}

- (void)_synchronize
{
    @synchronized(self) {
        NSDictionary *groupState = [self _groupStateFromGroups];
        _preferences[GroupStateKey] = groupState;

        if (IS_8_1()) {
            CFStringRef appID = CFSTR("com.a3tweaks.Apex");
            CFPreferencesSetMultiple((CFDictionaryRef)_preferences, NULL, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            return;
        }

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
            STKLog(@"Failed to write preferences to to output stream. Error %@: %@", @(err.code), err.localizedDescription);
        }
        else {
            NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
            NSURL *prefsURL = [NSURL fileURLWithPath:kPrefPath];
            [[NSFileManager defaultManager] replaceItemAtURL:prefsURL
                                               withItemAtURL:tempURL
                                              backupItemName:@"com.a3tweaks.Apex.last.plist"
                                                     options:(NSFileManagerItemReplacementUsingNewMetadataOnly | NSFileManagerItemReplacementWithoutDeletingBackupItem)
                                            resultingItemURL:NULL
                                                       error:&err];

            if (err) {
                STKLog(@"Failed to move preferences from temporary to primary path. Error Code %@: %@", @(err.code), err.localizedDescription);
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
        if (!group.centralIcon.leafIdentifier) {
            return;
        }
        if (group.state == STKGroupStateEmpty) {
            [_groups removeObjectForKey:group.centralIcon.leafIdentifier];
        }
        else {
            _groups[group.centralIcon.leafIdentifier] = group;
        }
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
- (void)groupDidFinalizeState:(STKGroup *)finalizedGroup
{
    if (finalizedGroup.state == STKGroupStateEmpty) {
        [self removeGroup:finalizedGroup];
        return;
    }
    NSMutableArray *groupsToUpdate = [NSMutableArray array];
    for (SBIcon *subappIcon in finalizedGroup.layout) {
        STKGroup *previousGroup = [[[self groupForSubappIcon:subappIcon] retain] autorelease];
        if (previousGroup && finalizedGroup != previousGroup) {
            // Another group has `subappIcon`, so remove subappIcon from it
            STKGroupSlot slotForRemovedIcon = [previousGroup.layout slotForIcon:subappIcon];
            [previousGroup replaceIconInSlot:slotForRemovedIcon withIcon:nil];
            [previousGroup forceRelayout];
            [groupsToUpdate addObject:previousGroup];
        }
    }
    [groupsToUpdate addObject:finalizedGroup];
    [self _addOrUpdateGroups:groupsToUpdate];
}

- (void)groupDidRelayout:(STKGroup *)group
{
    [self addOrUpdateGroup:group];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.a3tweaks.apex.iconstatechanged"),
                                         NULL,
                                         NULL,
                                         false);
}

static void
STKPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    [[STKPreferences sharedPreferences] reloadPreferences];
    [[NSNotificationCenter defaultCenter] postNotificationName:(NSString *)STKPrefsChangedNotificationName object:nil userInfo:nil];
}

@end

