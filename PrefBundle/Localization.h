#import <Foundation/Foundation.h>

static inline NSString *Localize(NSString *text)
{
	return [[NSBundle bundleWithPath:@"/Library/PreferenceBundles/ApexSettings.bundle"] localizedStringForKey:text value:text table:nil];
}
#define LOCALIZE(foo) Localize(@#foo)

#define ISPAD() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
