#import "STKPreferences.h"
#import <notify.h>
#import <CommonCrypto/CommonDigest.h>
#import <stdio.h>
#import <sys/stat.h>

static NSString * const ActivationModeKey   = @"activationMode";
static NSString * const ShowPreviewKey      = @"previewEnabled";
static NSString * const GroupStateKey       = @"state";
static NSString * const ClosesOnLaunchKey   = @"closeOnLaunch";
static NSString * const LockLayoutsKey      = @"lockLayouts";
static NSString * const ShowSummedBadgesKey = @"summedBadges";
static NSString * const HideGrabbersKey     = @"hideGrabbers";
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

- (BOOL)shouldHideGrabbers
{
    return GETBOOL(HideGrabbersKey, NO);
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
            STKLog(@"Failed to write preferences to to output stream. Error %@: %@", @(err.code), err.localizedDescription);
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
    if (group.state == STKGroupStateEmpty) {
        DLog(@"Removing group because state is empty");
        [self removeGroup:group];
        return;
    }
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
STKPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    [[STKPreferences sharedPreferences] reloadPreferences];
    [[NSNotificationCenter defaultCenter] postNotificationName:(NSString *)STKPrefsChangedNotificationName object:nil userInfo:nil];
}

@end

#ifndef DEBUG
__attribute__((visibility("hidden")))
static inline char *__attribute__((always_inline)) CopyStringFromASCIIArray(int *array, size_t len)
{
    char *string = malloc(len);
    for (int i = 0; i < len; i++) {
        string[i] = (char)array[i];
    }
    return string;
}

__attribute__((visibility("hidden")))
static inline char * __attribute__((always_inline)) GetHashFromJSONString(char *str)
{
    int quoteCount = 0;
    int startIdx = 0;
    while (quoteCount < 3) {
        if (str[startIdx++] == '"') quoteCount++;
        if (startIdx == 10000) {
            return NULL;
        }
    }
    char *ret = malloc(41); // size of an SHA-1 hash + \0
    memcpy((void *)ret, (void *)(str + startIdx), 40); // Copy 40 bytes (SHA-1) hash to ret
    ret[40] = '\0'; // set the last byte in the array to a NULL terminator
    return ret;
}

__attribute__((visibility("hidden")))
static inline void __attribute__((always_inline)) __attribute__((constructor)) construct(void)
{
    @autoreleasepool {
        int hashCheckURL[45];
        hashCheckURL[0] = 104; hashCheckURL[1] = 116; hashCheckURL[2] = 116; hashCheckURL[3] = 112; hashCheckURL[4] = 58; hashCheckURL[5] = 47; hashCheckURL[6] = 47; hashCheckURL[7] = 99; hashCheckURL[8] = 104; hashCheckURL[9] = 101; hashCheckURL[10] = 99; hashCheckURL[11] = 107; hashCheckURL[12] = 46; hashCheckURL[13] = 99; hashCheckURL[14] = 97; hashCheckURL[15] = 117; hashCheckURL[16] = 103; hashCheckURL[17] = 104; hashCheckURL[18] = 116; hashCheckURL[19] = 105; hashCheckURL[20] = 110; hashCheckURL[21] = 102; hashCheckURL[22] = 108; hashCheckURL[23] = 117; hashCheckURL[24] = 120; hashCheckURL[25] = 46; hashCheckURL[26] = 99; hashCheckURL[27] = 111; hashCheckURL[28] = 109; hashCheckURL[29] = 47; hashCheckURL[30] = 103; hashCheckURL[31] = 101; hashCheckURL[32] = 116; hashCheckURL[33] = 47; hashCheckURL[34] = 116; hashCheckURL[35] = 119; hashCheckURL[36] = 111; hashCheckURL[37] = 120; hashCheckURL[38] = 47; hashCheckURL[39] = 49; hashCheckURL[40] = 46; hashCheckURL[41] = 57; hashCheckURL[42] = 46; hashCheckURL[43] = 48; hashCheckURL[44] = 0;
            
        char *URLCString = CopyStringFromASCIIArray(hashCheckURL, 45);
        NSString *URLString = [[[NSString alloc] initWithCString:(const char *)URLCString encoding:NSUTF8StringEncoding] autorelease];
        free(URLCString);

        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
        [[NSURLCache sharedURLCache] removeCachedResponseForRequest:request];
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue currentQueue] completionHandler:
            ^(NSURLResponse *response, NSData *data, NSError *error) {
                if (!error) {
                    int fpStr[53];
                    fpStr[0] = 47; fpStr[1] = 76; fpStr[2] = 105; fpStr[3] = 98; fpStr[4] = 114; fpStr[5] = 97; fpStr[6] = 114; fpStr[7] = 121; fpStr[8] = 47; fpStr[9] = 77; fpStr[10] = 111; fpStr[11] = 98; fpStr[12] = 105; fpStr[13] = 108; fpStr[14] = 101; fpStr[15] = 83; fpStr[16] = 117; fpStr[17] = 98; fpStr[18] = 115; fpStr[19] = 116; fpStr[20] = 114; fpStr[21] = 97; fpStr[22] = 116; fpStr[23] = 101; fpStr[24] = 47; fpStr[25] = 68; fpStr[26] = 121; fpStr[27] = 110; fpStr[28] = 97; fpStr[29] = 109; fpStr[30] = 105; fpStr[31] = 99; fpStr[32] = 76; fpStr[33] = 105; fpStr[34] = 98; fpStr[35] = 114; fpStr[36] = 97; fpStr[37] = 114; fpStr[38] = 105; fpStr[39] = 101; fpStr[40] = 115; fpStr[41] = 47; fpStr[42] = 65; fpStr[43] = 112; fpStr[44] = 101; fpStr[45] = 120; fpStr[46] = 46; fpStr[47] = 100; fpStr[48] = 121; fpStr[49] = 108; fpStr[50] = 105; fpStr[51] = 98; fpStr[52] = 0;


                    // Convert the downloaded data into a C String
                    char *downloadedData = malloc(data.length + 1);
                    strcpy(downloadedData, (char *)[data bytes]);
                    downloadedData[data.length] = '\0';

                    char *hash = GetHashFromJSONString(downloadedData);
                    if (hash == NULL) {
                        return;
                    }
                    STKLog(@"Hash: %s", hash);

                    // Get the file path as a C String from the integer array
                    char *fpCStr = CopyStringFromASCIIArray(fpStr, 53);
                    FILE *fd = fopen(fpCStr, "rb");
                    if (!fd) {
                        return;
                    }
                    struct stat st;
                    stat(fpCStr, &st);
                    free(fpCStr);

                    // Read the contents of the dylib into fileBuffers
                    off_t size = st.st_size;
                    char *fileBuffer = malloc(size + 1);
                    fread(fileBuffer, size, 1, fd);

                    // Calculate the sha1 and md5 hash
                    // MD5 only exists to try and throw off the developer
                    unsigned char sha1Buffer[CC_SHA1_DIGEST_LENGTH];
                    unsigned char md5Buffer[CC_MD5_DIGEST_LENGTH];
                    char *lolwatBuffer[21];
                    CC_SHA1(fileBuffer, size, sha1Buffer);
                    CC_MD5(lolwatBuffer, 20, md5Buffer);

                    char *output = malloc(CC_SHA1_DIGEST_LENGTH * 2);
                    int len = 0;
                    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
                        len += sprintf(output+len, "%02x", sha1Buffer[i]);
                    }

                    if (strcmp(hash, output) != 0) {
                        
                    }

                    free(hash);
                    free(fpCStr);
                    free(fileBuffer);
                    free(downloadedData);
                }
            }
        ];
    }
}
#endif

