#import "STKPreferences.h"
#import "STKConstants.h"
#import "STKStackManager.h"

#import <CoreFoundation/CoreFoundation.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>
#import <notify.h>

#define kSTKSpringBoardPortName           CFSTR("com.a3tweaks.apex.springboardport")
#define kSTKSearchdPortName               CFSTR("com.a3tweaks.apex.searchdport")
#define kSTKIdentifiersRequestMessageName @"com.a3tweaks.apex.searchdwantshiddenidents"
#define kSTKIdentifiersRequestMessageID   (SInt32)1337
#define kSTKIdentifiersUpdateMessageID    (SInt32)1234

#define GETBOOL(_dict, _key, _default) (_dict[_key] ? [_dict[_key] boolValue] : _default);

static NSString * const STKStackPreviewEnabledKey = @"STKStackPreviewEnabled";

@interface STKPreferences ()
{   
    NSDictionary        *_currentPrefs;
    NSArray             *_layouts;
    NSArray             *_iconsInStacks;
    NSSet               *_iconsWithStacks;

    CFMessagePortRef     _localPort;
    BOOL                 _isSendingMessage;

    NSMutableArray      *_callbacks;
    NSMutableDictionary *_cachedLayouts;
}

- (void)_refreshGroupedIcons;
@end

@implementation STKPreferences

+ (NSString *)layoutsDirectory
{
    return [NSHomeDirectory() stringByAppendingString:@"/Library/Preferences/"kSTKTweakName@"/Layouts"];
}

+ (instancetype)sharedPreferences
{
    static id sharedInstance;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        sharedInstance = [[self alloc] init];

        [[NSFileManager defaultManager] createDirectoryAtPath:[self layoutsDirectory] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions : @511} error:NULL];
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @511} ofItemAtPath:[self layoutsDirectory] error:NULL]; // Set the persimissions to 755? Idk, it works.

        [sharedInstance reloadPreferences];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)STKPrefsChanged, STKPrefsChangedNotificationName, NULL, 0);
    });

    return sharedInstance;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _localPort = CFMessagePortCreateLocal(kCFAllocatorDefault, 
                                              kSTKSpringBoardPortName,
                                              (CFMessagePortCallBack)STKLocalPortCallBack,
                                              NULL,
                                              NULL);

        CFRunLoopSourceRef runLoopSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, _localPort, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
    }
    return self;
}

- (void)dealloc
{
    CFMessagePortInvalidate(_localPort);
    CFRelease(_localPort);

    [_currentPrefs release];
    [_layouts release];
    [_iconsInStacks release];
    [_iconsWithStacks release];
    [_cachedLayouts release];

    [super dealloc];
}

- (void)reloadPreferences
{
    [_currentPrefs release];

    _currentPrefs = [[NSDictionary alloc] initWithContentsOfFile:kPrefPath];
    if (!_currentPrefs) {
        _currentPrefs = [[NSMutableDictionary alloc] init];
        [(NSMutableDictionary *)_currentPrefs setObject:[NSNumber numberWithBool:YES] forKey:STKStackPreviewEnabledKey];
        [_currentPrefs writeToFile:kPrefPath atomically:YES];
    }

    [_layouts release];
    _layouts = nil;
    
    [_iconsInStacks release];
    _iconsInStacks = nil;

    [_iconsWithStacks release];
    _iconsWithStacks = nil;
}

- (BOOL)previewEnabled
{
    return GETBOOL(_currentPrefs, STKStackPreviewEnabledKey, YES);
}

- (NSSet *)identifiersForIconsWithStack
{
    static NSString * const fileType = @".layout";
    if (!_iconsWithStacks) {
        @synchronized(self) {
            if (!_layouts) {
                _layouts = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self class] layoutsDirectory] error:nil] retain];
            }

            NSMutableSet *identifiersSet = [[[NSMutableSet alloc] initWithCapacity:_layouts.count] autorelease];

            for (NSString *layout in _layouts) {
                if ([layout hasSuffix:fileType]) {
                    [identifiersSet addObject:[layout substringToIndex:(layout.length - fileType.length)]];
                }
            }

            _iconsWithStacks = [[NSSet alloc] initWithSet:identifiersSet];
        }
    }
    return _iconsWithStacks;
}

- (NSArray *)stackIconsForIcon:(SBIcon *)icon
{
    SBIconModel *model = [(SBIconController *)[objc_getClass("SBIconController") sharedInstance] model];

    NSDictionary *attributes = [NSDictionary dictionaryWithContentsOfFile:[self layoutPathForIcon:icon]];
    
    if (!attributes) {
        return nil;
    }

    NSMutableArray *stackIcons = [NSMutableArray arrayWithCapacity:(((NSArray *)attributes[STKStackManagerStackIconsKey]).count)];
    for (NSString *identifier in attributes[STKStackManagerStackIconsKey]) {
        // Get the SBIcon instances for the identifiers
        SBIcon *icon = [model expectedIconForDisplayIdentifier:identifier];
        if (icon) {
            [stackIcons addObject:[model expectedIconForDisplayIdentifier:identifier]];
        }
    }
    return stackIcons;
}

- (id)centralIconForIcon:(id)icon
{
    id ret = nil;

    if (_iconsWithStacks) {
        [self _refreshGroupedIcons];
    }

    BOOL wantsIcon = [icon isKindOfClass:[objc_getClass("SBIcon") class]];
    if (!wantsIcon && ![icon isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *identifier = (wantsIcon ? [(SBIcon *)icon leafIdentifier] : (NSString *)icon);

    // find the NSString object with the matching string
    NSUInteger ivarArrayIdx = [_iconsInStacks indexOfObject:identifier];
    if (ivarArrayIdx == NSNotFound) {
        return nil;
    }

    NSString *iconIDFromIvar = _iconsInStacks[ivarArrayIdx];
    ret = objc_getAssociatedObject(iconIDFromIvar, @selector(centralIconID));
    if (ret && wantsIcon) {
        ret = [[(SBIconController *)[objc_getClass("SBIconController") sharedInstance] model] expectedIconForDisplayIdentifier:(NSString *)ret];
    }

    return ret;
}

- (NSArray *)identifiersForIconsInStacks
{
    if (!_iconsInStacks) {
        [self _refreshGroupedIcons];
    }
    return _iconsInStacks;
}

- (NSString *)layoutPathForIconID:(NSString *)iconID
{
    return [NSString stringWithFormat:@"%@/%@.layout", [[self class] layoutsDirectory], iconID];
}

- (NSString *)layoutPathForIcon:(SBIcon *)icon
{
    return [self layoutPathForIconID:icon.leafIdentifier];
}

- (BOOL)iconHasStack:(SBIcon *)icon
{
    return (icon == nil ? NO : [[self identifiersForIconsWithStack] containsObject:icon.leafIdentifier]);
}

- (BOOL)iconIsInStack:(SBIcon *)icon
{
    if (!_iconsInStacks) {
        [self _refreshGroupedIcons];
    }

    return [_iconsInStacks containsObject:icon.leafIdentifier];
}

- (BOOL)removeLayoutForIcon:(SBIcon *)icon
{
    return [self removeLayoutForIconID:icon.leafIdentifier];
}

- (BOOL)removeLayoutForIconID:(NSString *)iconID
{
    @synchronized(self) {
        NSError *err = nil;
        BOOL ret = [[NSFileManager defaultManager] removeItemAtPath:[self layoutPathForIconID:iconID] error:&err];
        if (err) {
            STKLog(@"An error occurred when trying to remove layout for %@. Error %i, %@", iconID, err.code, err);
        }

        [self reloadPreferences];
        
        return ret;
    }
}

- (void)registerCallbackForPrefsChange:(STKPreferencesCallback)callbackBlock
{
    if (!callbackBlock) {
        return;
    }

    if (!_callbacks) {
        _callbacks = [NSMutableArray new];
    }

    [_callbacks addObject:[[callbackBlock copy] autorelease]];
}

- (NSDictionary *)cachedLayoutDictForIcon:(SBIcon *)centralIcon
{
    NSDictionary *layout = _cachedLayouts[centralIcon.leafIdentifier];
    if (!layout) {
        NSDictionary *customLayout = [NSDictionary dictionaryWithContentsOfFile:[[STKPreferences sharedPreferences] layoutPathForIcon:centralIcon]][STKStackManagerCustomLayoutKey];
        if (customLayout) {
            if (!_cachedLayouts) {
                _cachedLayouts = [NSMutableDictionary new];
            }
            _cachedLayouts[centralIcon.leafIdentifier] = customLayout;
            layout = customLayout;
        }
    } 

    return layout;
}

- (void)refreshCachedLayoutDictForIcon:(SBIcon *)centralIcon
{
    [_cachedLayouts removeObjectForKey:centralIcon.leafIdentifier];
}

- (void)_refreshGroupedIcons
{
    @synchronized(self) {
        [_iconsInStacks release];

        NSMutableArray *groupedIcons = [NSMutableArray array];
        NSSet *identifiers = [self identifiersForIconsWithStack];

        for (NSString *identifier in identifiers) {
            SBIcon *centralIcon = [[(SBIconController *)[objc_getClass("SBIconController") sharedInstance] model] expectedIconForDisplayIdentifier:identifier];
            
            for (NSString *groupedIconIdentifier in [(NSArray *)[self stackIconsForIcon:centralIcon] valueForKeyPath:@"leafIdentifier"]) {
                objc_setAssociatedObject(groupedIconIdentifier, @selector(centralIconID), identifier, OBJC_ASSOCIATION_COPY);
                [groupedIcons addObject:groupedIconIdentifier];
            }
        }

        _iconsInStacks = [groupedIcons copy];
    }
}

CFDataRef STKLocalPortCallBack(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info)
{
    CFDataRef returnData = NULL;
    if (data) {
        if (msgid == kSTKIdentifiersRequestMessageID) {
            if (![[STKPreferences sharedPreferences] valueForKey:@"_iconsInStacks"]) {
                [[STKPreferences sharedPreferences] _refreshGroupedIcons];
            }

            returnData = (CFDataRef)[[NSKeyedArchiver archivedDataWithRootObject:[[STKPreferences sharedPreferences] valueForKey:@"_iconsInStacks"]] retain];
            // Retain, because "The system releases the returned CFData object"
        }
    }
    
    return returnData;
}

static void STKPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    [[STKPreferences sharedPreferences] reloadPreferences];
    for (STKPreferencesCallback cb in [[STKPreferences sharedPreferences] valueForKey:@"_callbacks"]) {
        cb();
    }
}


@end
