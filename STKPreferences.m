#import "STKPreferences.h"
#import "STKConstants.h"
#import "STKStackManager.h"

#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

#define kLastEraseDateKey @"LastEraseDate"

@interface STKPreferences ()
{
    NSDictionary *_currentPrefs;
    NSArray      *_layouts;
    NSArray      *_iconsInGroups;
    NSSet        *_iconsWithStacks;
}

- (void)_refreshGroupedIcons;

@end

@implementation STKPreferences

+ (instancetype)sharedPreferences
{
    static id sharedInstance;
    
    if (!sharedInstance) {
        sharedInstance = [[self alloc] init];

        [[NSFileManager defaultManager] createDirectoryAtPath:[STKStackManager layoutsPath] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions : @511} error:NULL];
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @511} ofItemAtPath:[STKStackManager layoutsPath] error:NULL]; // Make sure the permissions are correct anyway

        [sharedInstance reloadPreferences];
    }

    return sharedInstance;
}

- (void)reloadPreferences
{
    [_currentPrefs release];
    [_layouts release];

    _currentPrefs = [[NSDictionary alloc] initWithContentsOfFile:kPrefPath];
    if (!_currentPrefs) {
        _currentPrefs = [[NSDictionary alloc] init];
        [_currentPrefs writeToFile:kPrefPath atomically:YES];
    }

    [_layouts release];
    _layouts = nil;
    
    [_iconsInGroups release];
    _iconsInGroups = nil;

    [_iconsWithStacks release];
    _iconsWithStacks = nil;
}

- (NSSet *)identifiersForIconsWithStack
{
    static NSString *fileType = @".layout";
    if (!_iconsWithStacks) {
        if (!_layouts) {
            _layouts = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[STKStackManager layoutsPath] error:nil] retain];
        }

        NSMutableSet *identifiersSet = [[[NSMutableSet alloc] initWithCapacity:_layouts.count] autorelease];

        for (NSString *layout in _layouts) {
            if ([layout hasSuffix:fileType]) {
                [identifiersSet addObject:[layout substringToIndex:(layout.length - fileType.length)]];
            }
        }

        _iconsWithStacks = [[NSSet alloc] initWithSet:identifiersSet];
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
        [stackIcons addObject:[model expectedIconForDisplayIdentifier:identifier]];
    }
    return stackIcons;
}


- (NSString *)layoutPathForIconID:(NSString *)iconID
{
    return [NSString stringWithFormat:@"%@/%@.layout", [STKStackManager layoutsPath], iconID];
}

- (NSString *)layoutPathForIcon:(SBIcon *)icon
{
    return [self layoutPathForIconID:icon.leafIdentifier];
}

- (BOOL)iconHasStack:(SBIcon *)icon
{
    return [[self identifiersForIconsWithStack] containsObject:icon.leafIdentifier];
}

- (BOOL)iconIsInStack:(SBIcon *)icon
{
    if (!_iconsInGroups) {
        [self _refreshGroupedIcons];
    }

    return [_iconsInGroups containsObject:icon.leafIdentifier];
}

- (BOOL)saveLayoutWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons
{
    return [self saveLayoutWithCentralIconID:centralIcon.leafIdentifier stackIconIDs:[icons valueForKeyPath:@"leafIdentifier"]];
}

- (BOOL)saveLayoutWithCentralIconID:(NSString *)iconID stackIconIDs:(NSArray *)stackIconIDs
{
    NSDictionary *attributes = @{STKStackManagerCentralIconKey : iconID,
                                 STKStackManagerStackIconsKey  : stackIconIDs}; // KVC FTW

    BOOL success = [attributes writeToFile:[self layoutPathForIconID:iconID] atomically:YES];
    if (success) {
        // Only reload if the write succeeded, hence save IO operations
        [self reloadPreferences];
    }

    return success;
}

- (void)_refreshGroupedIcons
{
    [_iconsInGroups release];

    NSMutableArray *groupedIcons = [NSMutableArray array];
    NSSet *identifiers = [self identifiersForIconsWithStack];
    for (NSString *identifier in identifiers) {
        SBIcon *centralIcon = [[(SBIconController *)[objc_getClass("SBIconController") sharedInstance] model] expectedIconForDisplayIdentifier:identifier];
        [groupedIcons addObjectsFromArray:[(NSArray *)[self stackIconsForIcon:centralIcon] valueForKeyPath:@"leafIdentifier"]];
    }

     _iconsInGroups = [groupedIcons copy];
}

@end
