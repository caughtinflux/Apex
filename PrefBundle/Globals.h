#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSRootController.h>
#import <Preferences/PSViewController.h>
#import "../STKConstants.h"

@interface UIImage(Extras)
+ (UIImage *)imageNamed:(NSString *)name inBundle:(NSBundle *)bundle;
@end

@interface UIDevice (iOS5)
- (id)deviceInfoForKey:(NSString *)key;
@end

@class PSSpecifier;

@interface PSListController : PSViewController
{
	NSArray *_specifiers;
}
- (UITableView *)table;
@property (nonatomic, readonly) NSArray *specifiers;
- (NSInteger)indexOfSpecifierID:(NSString *)specifierID;
- (PSSpecifier *)specifierAtIndex:(NSInteger)index;
- (void)removeSpecifierID:(NSString *)specifierID animated:(BOOL)animated;
- (void)insertSpecifier:(PSSpecifier *)specifier afterSpecifierID:(NSString *)otherSpecifierID animated:(BOOL)animated;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)plistName target:(id)target;
- (PSSpecifier*)specifierForID:(NSString*)specifierID;

@end
