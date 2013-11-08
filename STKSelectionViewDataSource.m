#import "STKConstants.h"
#import "STKSelectionViewDataSource.h"
#import "STKSelectionViewCell.h"
#import "STKPlaceHolderIcon.h"
#import "STKPreferences.h"

#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>

@interface STKSelectionViewDataSource ()
{
    NSMutableArray *_sections;
}
- (NSArray *)iconsInSection:(NSInteger)section;
@end

@implementation STKSelectionViewDataSource

- (void)dealloc
{
    [_sections release];
    [_centralView release];
    [super dealloc];
}

- (void)prepareData
{
    if (!_sections) {
        _sections = [NSMutableArray new];
    }
    
    NSMutableArray *availableIcons = [NSMutableArray array];
    SBIconModel *model = [(SBIconController *)[objc_getClass("SBIconController") sharedInstance] model];

    for (id ident in [model visibleIconIdentifiers]) {
        // Icons in a stack are removed from -[SBIconmodel visibleIconIdentifiers], so add those, and remove the central icon, and other icons with stacks
        if (ICONID_HAS_STACK(ident) || [ident isEqualToString:_centralView.icon.leafIdentifier]) {
            continue;
        }
        SBIcon *icon = [model expectedIconForDisplayIdentifier:ident];
        if (![icon isDownloadingIcon]) {
            [availableIcons addObject:[model expectedIconForDisplayIdentifier:ident]];
        }
    }

    for (NSString *hiddenIcon in [STKPreferences sharedPreferences].identifiersForIconsInStacks) {
        id icon = [model expectedIconForDisplayIdentifier:hiddenIcon];
        if (icon && ![availableIcons containsObject:icon]) {
            [availableIcons addObject:icon];
        }
    }

    // Add a placeholder to available icons so the user can have a "None"-like option
    STKPlaceHolderIcon *ph = [[[objc_getClass("STKPlaceHolderIcon") alloc] init] autorelease];
    [availableIcons addObject:ph];

    const SEL collationSelector = @selector(displayName);
    UILocalizedIndexedCollation *collation = [UILocalizedIndexedCollation currentCollation];
    NSInteger idx, sectionTitlesCount = [[collation sectionTitles] count];

    for (idx = 0; idx < sectionTitlesCount; idx++) {
        [_sections addObject:[NSMutableArray array]];
    }

    for (SBIcon *icon in availableIcons) {
        NSInteger sectionNumber = [collation sectionForObject:icon collationStringSelector:collationSelector];
        if (icon.isPlaceholder) {
            [[_sections objectAtIndex:0] insertObject:icon atIndex:0];
        }
        else {
            [[_sections objectAtIndex:sectionNumber] addObject:icon];
        }
    }

    for (idx = 0; idx < sectionTitlesCount; idx++) {
        NSArray *objectsForSection = [_sections objectAtIndex:idx];
        [_sections replaceObjectAtIndex:idx withObject:[collation sortedArrayFromArray:objectsForSection collationStringSelector:collationSelector]];
    }
}

- (SBIcon *)iconAtIndexPath:(NSIndexPath *)indexPath
{
    return [self iconsInSection:indexPath.section][indexPath.row];
}

- (NSIndexPath *)indexPathForIcon:(SBIcon *)icon
{
    NSInteger section = [[UILocalizedIndexedCollation currentCollation] sectionForObject:icon collationStringSelector:@selector(displayName)];
    NSInteger row = [[self iconsInSection:section] indexOfObject:icon];
    if (row == NSNotFound) {
        return nil;
    }

    return [NSIndexPath indexPathForRow:row inSection:section];
}

- (NSArray *)iconsInSection:(NSInteger)section
{
    return _sections[section];
}

#pragma mark - UITableView Data Source
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString * const CellIdentifier = @"STKIconCell";

    STKSelectionViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
    cell.icon = [self iconAtIndexPath:indexPath];
    cell.position = _cellPosition;

    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return _sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self iconsInSection:section].count;
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    return ([[STKPreferences sharedPreferences] shouldShowSectionIndexTitles] ? [[UILocalizedIndexedCollation currentCollation] sectionIndexTitles] : nil);
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index 
{
    return [[UILocalizedIndexedCollation currentCollation] sectionForSectionIndexTitleAtIndex:index];
}

@end
