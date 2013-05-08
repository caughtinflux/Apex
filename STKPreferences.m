#import "STKPreferences.h"
#import "STKConstants.h"
#import "STKStackManager.h"

#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIconModel.h>
#import <SpringBoard/SBIcon.h>

#import <objc/runtime.h>

#define kIconsWithStackKey @"STKIconsWithStack"

@interface STKPreferences ()
{
    NSDictionary *_currentPrefs;
    NSArray      *_layouts;
}
@end

@implementation STKPreferences

+ (instancetype)sharedPreferences
{
    static id sharedInstance;
    
    if (!sharedInstance) {
        sharedInstance = [[self alloc] init];
        if (![[NSFileManager defaultManager] fileExistsAtPath:[STKStackManager layoutsPath]]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[STKStackManager layoutsPath] withIntermediateDirectories:YES attributes:nil error:NULL];
        }
    }

    return sharedInstance;
}

- (instancetype)init
{
    if ((self = [super init])) {
        // Get the latest stuff, store them into ivars
        // No need to init from file every damn time.
        [self reloadPreferences];
    }
    return self;
}

- (NSArray *)identifiersForIconsWithStack
{
    static NSString *fileType = @".layout";
    NSMutableArray *identifiers = [NSMutableArray arrayWithCapacity:_layouts.count];

    for (NSString *layout in _layouts) {
        if ([layout hasSuffix:fileType]) {
            [identifiers addObject:[layout substringToIndex:(layout.length - fileType.length)]];
        }
    }
    return identifiers;
}

- (NSArray *)stackIconsForIcon:(SBIcon *)icon
{
    SBIconModel *model = [(SBIconController *)[objc_getClass("SBIconController") sharedInstance] model];

    NSDictionary *attributes = [NSDictionary dictionaryWithContentsOfFile:[self layoutPathForIcon:icon]];

    NSMutableArray *stackIcons = [NSMutableArray arrayWithCapacity:(((NSArray *)attributes[STKStackManagerStackIconsKey]).count)];
    for (NSString *identifier in attributes[STKStackManagerCentralIconKey]) {
        // Get the SBIcon instances for the identifiers
        [stackIcons addObject:[model applicationIconForDisplayIdentifier:identifier]];
    }
    return stackIcons;
}

- (NSString *)layoutPathForIcon:(SBIcon *)icon
{
    return [NSString stringWithFormat:@"%@/%@.layout", [STKStackManager layoutsPath], icon.leafIdentifier];
}

- (void)reloadPreferences
{
    _currentPrefs = [[NSDictionary alloc] initWithContentsOfFile:kPrefPath];
    if (!_currentPrefs) {
        _currentPrefs = [[NSDictionary alloc] init];
    }
    _layouts = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[STKStackManager layoutsPath] error:nil] retain];

}

- (BOOL)iconHasStack:(SBIcon *)icon
{
    return [[self identifiersForIconsWithStack] containsObject:icon.leafIdentifier];
}

@end
