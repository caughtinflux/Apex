#import "STKConfigurationController.h"
#import "Localization.h"
#import "../STKConstants.h"

#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSRootController.h>

static NSString * const PreviewSpecifierID   = @"SUBAPP_PREVIEWS";
static NSString * const GrabberSpecifierID   = @"GRABBERS";
static NSString * const NoneSpecifierID      = @"NONE";
static NSString * const SwipeUpSpecifierID   = @"SWIPE_UP";
static NSString * const SwipeDownSpecifierID = @"SWIPE_DOWN_ACCESS";
static NSString * const DoubleTapSpecifierID = @"DOUBLE_TAP";
static NSString * const TapToSpotlightID     = @"TAP_SB";
static NSString * const SwipeToSpotlightID   = @"SWIPE_DOWN_SPOTLIGHT";

@implementation STKConfigurationController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = LOCALIZE(CONFIGURATION);
}

- (id)specifiers
{
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"ConfigSpecs" target:self] retain];
    }
    return _specifiers;
}

- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target
{
    id specifiers = [super loadSpecifiersFromPlistName:name target:target];
    for (PSSpecifier *specifier in specifiers) {
        [specifier setName:Localize([specifier name])];
    }
    return specifiers;
}

- (BOOL)canBeShownFromSuspendedState
{
    return NO;
}

- (void)_setValue:(NSNumber *)value forMultiSelectionSpecifiers:(NSArray *)specifiers
{
    for (PSSpecifier *spec in specifiers) {
        [[self cellForSpecifier:spec] setChecked:[value boolValue]];
        [self setPreferenceValue:value specifier:spec];
        [self setPreferenceValue:value specifier:spec];
        [[[self rootController] class] writePreference:spec];
    }
}

- (void)setVisualIndicator:(PSSpecifier *)selectedSpecifier
{
    PSSpecifier *previewSpecifier = [self specifierForID:PreviewSpecifierID];
    PSSpecifier *grabberSpecifier = [self specifierForID:GrabberSpecifierID];
    PSSpecifier *noneSpecifier = [self specifierForID:NoneSpecifierID];

    NSMutableArray *specifiersToTurnOff = [[@[grabberSpecifier, previewSpecifier, noneSpecifier] mutableCopy] autorelease];
    [specifiersToTurnOff removeObject:selectedSpecifier];
    [self _setValue:@NO forMultiSelectionSpecifiers:specifiersToTurnOff];
    [self _setValue:@YES forMultiSelectionSpecifiers:@[selectedSpecifier]];
}

- (void)updateSpecifier:(PSSpecifier *)specifier
{
    BOOL newSetting = ![[self readPreferenceValue:specifier] boolValue];
    PSTableCell *cell = [self cellForSpecifier:specifier];
    [cell setChecked:newSetting];
    [self setPreferenceValue:@(newSetting) specifier:specifier];
    [[[self rootController] class] writePreference:specifier];
}

- (PSTableCell *)cellForSpecifier:(PSSpecifier *)specifier
{
    return (PSTableCell *)[[self table] cellForRowAtIndexPath:[self indexPathForSpecifier:specifier]];
}

- (PSTableCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *specifiersToModify = @[
        [self specifierForID:PreviewSpecifierID],
        [self specifierForID:GrabberSpecifierID],
        [self specifierForID:NoneSpecifierID],
        [self specifierForID:SwipeUpSpecifierID],
        [self specifierForID:SwipeDownSpecifierID],
        [self specifierForID:DoubleTapSpecifierID],
        [self specifierForID:TapToSpotlightID],
        [self specifierForID:SwipeToSpotlightID]
    ];

    PSTableCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = cell.specifier;
    if ([specifiersToModify containsObject:spec]) {
        NSNumber *val = [self readPreferenceValue:spec];
        [cell setChecked:[val boolValue]];
    }
    return cell;
}

@end
