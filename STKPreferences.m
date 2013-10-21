#import "STKPreferences.h"
#import "STKConstants.h"
#import "STKStack.h"

#import <CoreFoundation/CoreFoundation.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>
#import <notify.h>

#define GETBOOL(_dict, _key, _default) (_dict[_key] ? [_dict[_key] boolValue] : _default);

static NSString * const STKWelcomeAlertShownKey   = @"STKWelcomeAlertShown";
static NSString * const STKStackPreviewEnabledKey = @"STKStackPreviewEnabled";
static NSString * const STKHideGrabbersKey        = @"STKHideGrabbers";
static NSString * const STKStackClosesOnLaunchKey = @"STKStackClosesOnLaunch";
static NSString * const STKShowSectionTitlesKey   = @"STKShowSectionTitles";

@interface STKPreferences ()
{   
    NSMutableDictionary *_currentPrefs;
    NSArray             *_layouts;
    NSArray             *_iconsInStacks;
    NSSet               *_iconsWithStacks;

    NSMutableArray      *_callbacks;
    NSMutableDictionary *_cachedLayouts;
}

- (void)_refreshGroupedIcons;
@end

@implementation STKPreferences

#pragma mark - Layout Paths
+ (NSString *)layoutsDirectory
{
    return [NSHomeDirectory() stringByAppendingString:@"/Library/Preferences/"kSTKTweakName@"/Layouts"];
}

+ (NSString *)layoutPathForIconID:(NSString *)iconID
{
    return [NSString stringWithFormat:@"%@/%@.layout", [self layoutsDirectory], iconID];
}

+ (NSString *)layoutPathForIcon:(SBIcon *)icon
{
    return [self layoutPathForIconID:icon.leafIdentifier];
}

#pragma mark - Layout Validation
+ (BOOL)isValidLayoutAtPath:(NSString *)path
{
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!dict) {
        return NO;
    }

    return [self isValidLayout:dict];
}

+ (BOOL)isValidLayout:(NSDictionary *)dict
{
    SBIconModel *model = (SBIconModel *)[[objc_getClass("SBIconController") sharedInstance] model];
    NSArray *stackIconIDs = dict[STKStackManagerStackIconsKey];

    if (![model expectedIconForDisplayIdentifier:dict[STKStackManagerCentralIconKey]] || !stackIconIDs) {
        return NO;
    }

    NSUInteger count = 0;
    for (NSString *ident in stackIconIDs) {
        if ([model expectedIconForDisplayIdentifier:ident]) {
            count++;
        }
    }

    if (count == 0) {
        return NO;
    }

    return YES;
}

#pragma mark - Layout Persistence
+ (void)saveLayout:(STKIconLayout *)layout forIcon:(SBIcon *)centralIcon
{
    NSMutableDictionary *dictionaryRepresentation = [[[layout dictionaryRepresentation] mutableCopy] autorelease];
    STKIconCoordinates coords = [STKIconLayoutHandler coordinatesForIcon:centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    dictionaryRepresentation[@"xPos"] = [NSNumber numberWithInteger:coords.xPos];
    dictionaryRepresentation[@"yPos"] = [NSNumber numberWithInteger:coords.yPos];

    NSDictionary *fileDict = @{ STKStackManagerCentralIconKey  : centralIcon.leafIdentifier,
                                STKStackManagerStackIconsKey   : [[layout allIcons] valueForKeyPath:@"leafIdentifier"],
                                STKStackManagerCustomLayoutKey : dictionaryRepresentation};

    [fileDict writeToFile:[self layoutPathForIcon:centralIcon] atomically:YES];
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

- (void)dealloc
{
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

    _currentPrefs = [[NSMutableDictionary alloc] initWithContentsOfFile:kPrefPath];
    if (!_currentPrefs) {
        _currentPrefs = [[NSMutableDictionary alloc] init];
        // Set the default values
        _currentPrefs[STKStackPreviewEnabledKey] = @YES;
        _currentPrefs[STKStackClosesOnLaunchKey] = @YES;
        _currentPrefs[STKShowSectionTitlesKey] = @YES;

        [_currentPrefs writeToFile:kPrefPath atomically:YES];
    }

    [_layouts release];
    _layouts = nil;
    
    [_iconsInStacks release];
    _iconsInStacks = nil;

    [_iconsWithStacks release];
    _iconsWithStacks = nil;

    [_cachedLayouts release];
    _cachedLayouts = nil;

    notify_post("com.a3tweaks.apex.layoutschanged");
}

- (BOOL)welcomeAlertShown
{
    return GETBOOL(_currentPrefs, STKWelcomeAlertShownKey, NO);
}

- (BOOL)previewEnabled
{
    return GETBOOL(_currentPrefs, STKStackPreviewEnabledKey, YES);
}

- (BOOL)shouldHideGrabbers
{
    return GETBOOL(_currentPrefs, STKHideGrabbersKey, NO);
}

- (BOOL)shouldCloseOnLaunch
{
    return GETBOOL(_currentPrefs, STKStackClosesOnLaunchKey, YES);
}

- (BOOL)shouldShowSectionIndexTitles
{
    return GETBOOL(_currentPrefs, STKShowSectionTitlesKey, YES);
}

- (void)setWelcomeAlertShown:(BOOL)shown
{
    @synchronized(self) {
        NSMutableDictionary *dict = [_currentPrefs mutableCopy];
        dict[STKWelcomeAlertShownKey] = [NSNumber numberWithBool:shown];
        [_currentPrefs release];
        _currentPrefs = [dict copy];

        [_currentPrefs writeToFile:kPrefPath atomically:YES];
    }
}

- (NSSet *)identifiersForIconsWithStack
{
    static NSString * const fileType = @".layout";
    if (!_iconsWithStacks) {
        @synchronized(self) {
            if (!_layouts) {
                _layouts = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[STKPreferences layoutsDirectory] error:nil] retain];
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

    NSDictionary *attributes = [NSDictionary dictionaryWithContentsOfFile:[STKPreferences layoutPathForIcon:icon]];
    
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
    if (iconID == nil) {
        return NO;
    }
    @synchronized(self) {
        NSError *err = nil;
        BOOL ret = [[NSFileManager defaultManager] removeItemAtPath:[STKPreferences layoutPathForIconID:iconID] error:&err];
        if (err) {
#ifndef __x86_64__
            STKLog(@"An error occurred when trying to remove layout for %@. Error %i, %@", iconID, err.code, err);
#endif
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
        NSString *layoutPath = [STKPreferences layoutPathForIcon:centralIcon];
        if (![STKPreferences isValidLayoutAtPath:layoutPath]) {
            [[STKPreferences sharedPreferences] removeLayoutForIcon:centralIcon];
            return nil;
        }
        
        NSDictionary *customLayout = [NSDictionary dictionaryWithContentsOfFile:layoutPath][STKStackManagerCustomLayoutKey];
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

- (void)removeCachedLayoutForIcon:(SBIcon *)centralIcon
{
    if (centralIcon.leafIdentifier) {
        [_cachedLayouts removeObjectForKey:centralIcon.leafIdentifier];
    }
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

static void STKPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    [[STKPreferences sharedPreferences] reloadPreferences];
    for (STKPreferencesCallback cb in [[STKPreferences sharedPreferences] valueForKey:@"_callbacks"]) {
        cb();
    }
}


@end
