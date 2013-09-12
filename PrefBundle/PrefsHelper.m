#import "PrefsHelper.h"

#define bundlePath @"/Library/PreferenceBundles/ApexSettings.bundle"

@implementation STKPrefsHelper

+ (instancetype)sharedHelper
{
    static id __sharedInstance;
    if (!__sharedInstance) {
        __sharedInstance = [[self alloc] init];
    }
    return __sharedInstance;
}

- (id)init
{
    if ((self = [super init]))
    {
        ownBundle = [[NSBundle alloc] initWithPath:bundlePath];
    }
    return self;
}

- (UIImage *)ownImageNamed:(NSString *)name
{
    return [UIImage imageNamed:name inBundle:ownBundle];
}

- (NSString *)ownStringForKey:(NSString *)key
{
    return [ownBundle localizedStringForKey:key value:nil table:nil];
}

- (NSBundle *)ownBundle
{
    return ownBundle;
}

- (void) dealloc
{
    [ownBundle release];
    [super dealloc];
}

@end
