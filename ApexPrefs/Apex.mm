#import <Preferences/Preferences.h>

@interface ApexListController: PSListController {
}
@end

@implementation ApexListController
- (id)specifiers {
	if(_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"Apex" target:self] retain];
	}
	return _specifiers;
}
@end

// vim:ft=objc
