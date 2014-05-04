#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKSelectionViewCell.h"
#import "STKSelectionHeaderView.h"
#import "STKSelectionTitleTextField.h"
#import <SpringBoard/SpringBoard.h>

#define kCellReuseIdentifier @"STKSelectionViewCell"
#define kHeaderReuseIdentifier @"OMEMGEE!"

@implementation STKSelectionView
{
    UIView *_contentView;
    UICollectionView *_collectionView;
    SBFolderBackgroundView *_backgroundView;
    SBIcon *_selectedIcon;
    SBIcon *_centralIcon;
    SBIconView *_selectedIconView;
    STKSelectionTitleTextField *_searchTextField;

    NSArray *_recommendedApps;
    NSArray *_allApps;
    NSArray *_searchResults;
    BOOL _hasRecommendations;
    BOOL _isSearching;
}

- (instancetype)initWithFrame:(CGRect)frame selectedIcon:(SBIcon *)selectedIcon centralIcon:(SBIcon *)centralIcon
{   
    if ((self = [super initWithFrame:frame])) {
        _selectedIcon = [selectedIcon retain];
        _centralIcon = [centralIcon retain];

        _contentView = [[UIView alloc] initWithFrame:self.bounds];

        UICollectionViewFlowLayout *flowLayout = [[[UICollectionViewFlowLayout alloc] init] autorelease];
        flowLayout.itemSize = [CLASS(SBIconView) defaultIconSize];

        _collectionView = [[[UICollectionView alloc] initWithFrame:_contentView.bounds collectionViewLayout:flowLayout] autorelease];
        _collectionView.delegate = self;
        _collectionView.dataSource = self;
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.layer.cornerRadius = (ISPAD() ? 58.f : 35.f);
        _collectionView.layer.masksToBounds = YES;
        _collectionView.allowsSelection = YES;
        _collectionView.scrollIndicatorInsets = ISPAD() ? (UIEdgeInsets){35.f, 0.f, 35.f, 0.f} : (UIEdgeInsets){28.f, 0.f, 28.f, 0.f};
        _collectionView.backgroundView = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
        _collectionView.bounces = YES;
        _collectionView.alwaysBounceVertical = YES;
        [_collectionView registerClass:[STKSelectionViewCell class] forCellWithReuseIdentifier:kCellReuseIdentifier];
        [_collectionView registerClass:[STKSelectionHeaderView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:kHeaderReuseIdentifier];

        _backgroundView = [[CLASS(SBFolderBackgroundView) alloc] initWithFrame:_contentView.frame];
        _backgroundView.center = _collectionView.center;

        [_contentView addSubview:_backgroundView];
        [_contentView addSubview:_collectionView];
        [self addSubview:_contentView];
        [self _setupTextField];
    }
    return self;
}

- (void)dealloc
{
    [_searchResults release];
    [_recommendedApps release];
    [_allApps release];
    [_selectedIcon release];
    [_centralIcon release];
    [_contentView release];
    [super dealloc];
}

- (void)layoutSubviews
{
    _contentView.center = (CGPoint){CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds)};
    _collectionView.frame = _backgroundView.frame = _contentView.bounds;
}

- (UIView *)contentView
{
    return _contentView;
}

- (UIView *)iconCollectionView
{
    return _collectionView;
}

- (void)setIconsForSelection:(NSArray *)icons
{
    _iconsForSelection = [icons copy];
    [self _processIcons:icons];
    [_collectionView reloadData];
}

- (BOOL)isKeyboardVisible
{
    return [_searchTextField isFirstResponder];
}

- (void)scrollToSelectedIconAnimated:(BOOL)animated
{
    if ([_selectedIcon isLeafIcon]) {
        NSUInteger itemIndex = 0;
        NSUInteger itemSection = 0;
        if (_hasRecommendations) {
            // If we have recommendations, then modify the section accordingly
            if ((itemIndex = [_recommendedApps indexOfObject:_selectedIcon]) != NSNotFound) {
                itemSection = 0;
            }
            else if ((itemIndex = [_allApps indexOfObject:_selectedIcon]) != NSNotFound) {
                itemSection = 1;
            }
        }
        else {
            itemIndex = [_allApps indexOfObject:_selectedIcon];
            itemSection = 0;
        }
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:itemIndex inSection:itemSection];
        if (![[_collectionView indexPathsForVisibleItems] containsObject:indexPath]) {
            [_collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionCenteredVertically];
        }
    }
}

- (void)flashScrollIndicators
{
    [_collectionView flashScrollIndicators];
}

- (void)dismissKeyboard
{
    [_searchTextField resignFirstResponder];
}

- (void)_processIcons:(NSArray *)icons
{
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"displayName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    icons = [icons sortedArrayUsingDescriptors:@[sortDescriptor]];

    NSMutableArray *iconsSimilarToSelectedIcon = [NSMutableArray array];
    NSMutableArray *allIcons = [NSMutableArray array];
    NSSet *centralIconGenres = [NSSet setWithArray:[_centralIcon folderTitleOptions]];
    for (SBIcon *icon in icons) {
        if (icon == _centralIcon || [icon iconAppearsInNewsstand] || [icon isNewsstandApplicationIcon] || [icon isNewsstandIcon]) {
            continue;
        }
        NSSet *iconGenres = [NSSet setWithArray:[icon folderTitleOptions]];
        if ([centralIconGenres intersectsSet:iconGenres]) {
            // icons with similar title options are to be grouped together
            [iconsSimilarToSelectedIcon addObject:icon];
        }
        [allIcons addObject:icon];
    }

    _hasRecommendations = (iconsSimilarToSelectedIcon.count > 0);
    _recommendedApps = [iconsSimilarToSelectedIcon retain];
    _allApps = [allIcons retain];
}

- (NSArray *)_iconsForSection:(NSInteger)section
{
    if (section == 0) {
        if (_isSearching) return _searchResults;
        if (_hasRecommendations) return _recommendedApps;
        return _allApps;
    }
    if (section == 1) {
        return _allApps;
    }
    return nil;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return ((!_hasRecommendations || _isSearching) ? 1 : 2);
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self _iconsForSection:section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    STKSelectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCellReuseIdentifier forIndexPath:indexPath];
    SBIcon *icon = [self _iconsForSection:indexPath.section][indexPath.item];
    cell.iconView.icon = icon;
    cell.iconView.delegate = cell;
    if (cell.iconView.icon == _selectedIcon) {
        [cell.iconView showApexOverlayOfType:STKOverlayTypeCheck];
        [cell.iconView setNeedsLayout];
        [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    }
    else {
        if ([indexPath compare:[[collectionView indexPathsForSelectedItems] firstObject]] == NSOrderedSame) {
            [collectionView deselectItemAtIndexPath:indexPath animated:NO];
        }
        [cell.iconView removeApexOverlay];
    }
    [cell.iconView setHighlighted:NO];
    cell.tapHandler = ^(STKSelectionViewCell *tappedCell) {
        [self _selectedCell:[[tappedCell retain] autorelease]];
    };
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [CLASS(SBIconView) defaultIconSize];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section
{
    return (CGSize){0, 30.f};
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section
{
    UIEdgeInsets insets = [self collectionView:collectionView layout:collectionViewLayout insetForSectionAtIndex:section];
    CGSize size = [CLASS(SBIconView) defaultIconSize];
    CGFloat spacing = (collectionView.frame.size.width - ((size.width * 3) + insets.left + insets.right)) / 3.f;
    return spacing;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section
{
    CGSize size = [CLASS(SBIconView) defaultIconSize];
    UIEdgeInsets insets = [self collectionView:collectionView layout:collectionViewLayout insetForSectionAtIndex:section];
    CGFloat numItems = (ISPAD() ? 3.5 : 3.1f);
    CGFloat height = (collectionView.frame.size.height - ((size.height * numItems) + insets.top + insets.bottom)) /  numItems;
    return height;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section
{
    return (ISPAD() ? (UIEdgeInsets){10.f, 35.f, 25.f, 35.f} : (UIEdgeInsets){10, 20.f, 30.f, 20.f});
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    STKSelectionHeaderView *view = (STKSelectionHeaderView *)[collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader 
                                                                                                withReuseIdentifier:kHeaderReuseIdentifier
                                                                                                       forIndexPath:indexPath];
    if (indexPath.section == 0) {
        if (_isSearching) {
            view.headerTitle = @"Search Results";
        }
        else if (_hasRecommendations) {
            view.headerTitle = @"Recommended";
        }
        else {
            view.headerTitle = @"All";
        }
    }
    else {
        view.headerTitle = @"All";
    }
    return view;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [_searchTextField resignFirstResponder];
    STKSelectionViewCell *selectedCell = (STKSelectionViewCell *)[_collectionView cellForItemAtIndexPath:[[_collectionView indexPathsForSelectedItems] firstObject]];
    [selectedCell.iconView setHighlighted:NO];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    STKSelectionViewCell *selectedCell = (STKSelectionViewCell *)[_collectionView cellForItemAtIndexPath:[[_collectionView indexPathsForSelectedItems] firstObject]];
    [selectedCell.iconView setHighlighted:NO];   
}

- (void)_selectedCell:(STKSelectionViewCell *)cell
{
    NSIndexPath *previousIndexPath = [[_collectionView indexPathsForSelectedItems] firstObject];
    STKSelectionViewCell *previousSelection = (STKSelectionViewCell *)[_collectionView cellForItemAtIndexPath:previousIndexPath];
    [previousSelection.iconView removeApexOverlay];
    [_collectionView deselectItemAtIndexPath:previousIndexPath animated:NO];

    if (_selectedIcon == cell.iconView.icon) {
        _selectedIcon = nil;
        return;
    }
    _selectedIcon = cell.iconView.icon;
    
    NSIndexPath *currentIndexPath = [_collectionView indexPathForCell:cell];
    STKSelectionViewCell *currentSelection = (STKSelectionViewCell *)[_collectionView cellForItemAtIndexPath:currentIndexPath];
    [currentSelection.iconView showApexOverlayOfType:STKOverlayTypeCheck];
    [_collectionView selectItemAtIndexPath:currentIndexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    [_searchTextField resignFirstResponder];
    if (self.selectionHandler) {
        self.selectionHandler();
    }
}

- (void)_setupTextField
{
    _searchTextField = [[[STKSelectionTitleTextField alloc] initWithFrame:(CGRect){{15.f, 46.f}, {290.f, 40.f}}] autorelease];
    CGRect frame = _searchTextField.frame;
    frame.size.width = [CLASS(SBFolderBackgroundView) folderBackgroundSize].width;
    if (ISPAD()) {
        frame.size.height *= 1.5f;
    }
    _searchTextField.frame = frame;
    UIScreen *screen = [UIScreen mainScreen];
    CGFloat width = UIInterfaceOrientationIsPortrait([UIApplication sharedApplication].statusBarOrientation) ? screen.bounds.size.width : screen.bounds.size.height;
    _searchTextField.center = (CGPoint){(width * 0.5f), (frame.origin.y + (frame.size.height * 0.5))};
    _searchTextField.delegate = self;
    _searchTextField.attributedPlaceholder = [self _attributedPlaceholderForTextField];
    _searchTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    [_searchTextField addTarget:self action:@selector(_searchTextChanged) forControlEvents:UIControlEventEditingChanged];
    [self addSubview:_searchTextField];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    textField.textAlignment = NSTextAlignmentLeft;
    textField.textColor = [UIColor whiteColor];
    textField.attributedPlaceholder = nil;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    textField.textAlignment = NSTextAlignmentCenter;
    textField.textColor = [UIColor whiteColor];
    _searchTextField.attributedPlaceholder = [self _attributedPlaceholderForTextField];
    if (_searchTextField.text.length > 0) {
        _searchTextField.rightViewMode = UITextFieldViewModeAlways;
    }
    else {
        _searchTextField.rightViewMode = UITextFieldViewModeWhileEditing;
    }
}

- (void)_searchTextChanged
{
    [_searchResults release];
    _searchResults = nil;
    if (_searchTextField.text.length == 0) {
        _isSearching = NO;
        [_collectionView reloadData];
        return;
    }
    _isSearching = YES;

    NSMutableArray *searchResults = [NSMutableArray new];
    for (SBIcon *icon in _allApps) {
        if ([[icon displayName] rangeOfString:_searchTextField.text options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)].location != NSNotFound) {
            [searchResults addObject:icon];
        }
    }
    _searchResults = searchResults;
    [_collectionView reloadData];
}

- (BOOL)textFieldShouldClear:(UITextField *)textField
{
    _isSearching = NO;
    [_searchResults release];
    _searchResults = nil;
    [_collectionView reloadData];
    return YES;
}

- (NSAttributedString *)_attributedPlaceholderForTextField
{
    return [[[NSAttributedString alloc] initWithString:@"Select Sub-App"
                                            attributes:@{NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Light" size:24.f],
                                                         NSForegroundColorAttributeName: [UIColor colorWithWhite:1.f alpha:0.5f]}] autorelease];
}

@end
