#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKSelectionViewCell.h"
#import "STKSelectionHeaderView.h"
#import <SpringBoard/SpringBoard.h>

#define kCellReuseIdentifier @"STKSelectionViewCell"
#define kHeaderReuseIdentifier @"OMEMGEE!"

@implementation STKSelectionView
{
    UICollectionView *_collectionView;
    SBFolderBackgroundView *_backgroundView;
    SBIcon *_selectedIcon;
    SBIcon *_centralIcon;
    SBIconView *_selectedIconView;

    NSArray *_recommendedApps;
    NSArray *_allApps;
    BOOL _hasRecommendations;
}

- (instancetype)initWithFrame:(CGRect)frame selectedIcon:(SBIcon *)selectedIcon centralIcon:(SBIcon *)centralIcon
{   
    if ((self = [super initWithFrame:frame])) {
        _selectedIcon = [selectedIcon retain];
        _centralIcon = [centralIcon retain];
        UICollectionViewFlowLayout *flowLayout = [[[UICollectionViewFlowLayout alloc] init] autorelease];
        flowLayout.itemSize = [CLASS(SBIconView) defaultIconSize];

        _collectionView = [[[UICollectionView alloc] initWithFrame:self.bounds collectionViewLayout:flowLayout] autorelease];
        _collectionView.delegate = self;
        _collectionView.dataSource = self;
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.layer.cornerRadius = 35.f; // the default corner radius for folders, apparently.
        _collectionView.layer.masksToBounds = YES;
        _collectionView.allowsSelection = YES;
        _collectionView.contentInset = (UIEdgeInsets){10.f, 0.f, 0.f, 0.f};
        _collectionView.scrollIndicatorInsets = (UIEdgeInsets){25.f, 0.f, 25.f, 0.f};
        self.autoresizingMask = _collectionView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        [_collectionView registerClass:[STKSelectionViewCell class] forCellWithReuseIdentifier:kCellReuseIdentifier];
        [_collectionView registerClass:[STKSelectionHeaderView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:kHeaderReuseIdentifier];

        _backgroundView = [[CLASS(SBFolderBackgroundView) alloc] initWithFrame:self.bounds];
        [self addSubview:_backgroundView];
        _collectionView.backgroundView = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];

        [self addSubview:_collectionView];
    }
    return self;
}

- (void)dealloc
{
    [_selectedIcon release];
    [_centralIcon release];
    [super dealloc];
}

- (void)layoutSubviews
{
    _backgroundView.frame = self.bounds;
}

- (UIView *)contentView
{
    return _collectionView;
}

- (void)setIconsForSelection:(NSArray *)icons
{
    _iconsForSelection = [icons copy];
    [self _processIcons:icons];
    [_collectionView reloadData];
}

- (void)flashScrollIndicators
{
    [_collectionView flashScrollIndicators];
}

- (void)_processIcons:(NSArray *)icons
{
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"displayName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    icons = [icons sortedArrayUsingDescriptors:@[sortDescriptor]];

    NSMutableArray *iconsSimilarToSelectedIcon = [NSMutableArray array];
    NSMutableArray *allIcons = [NSMutableArray array];
    NSSet *centralIconGenres = [NSSet setWithArray:[_centralIcon folderTitleOptions]];
    for (SBIcon *icon in icons) {
        if (icon == _centralIcon) continue;

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
        return (_hasRecommendations ? _recommendedApps : _allApps);
    }
    if (section == 1) {
        return _allApps;
    }
    return nil;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return (_hasRecommendations ? 2 : 1);
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
    if (cell.iconView.icon == _selectedIcon) {
        [cell.iconView showApexOverlayOfType:STKOverlayTypeEditing];
        [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    }
    else {
        if ([indexPath compare:[[collectionView indexPathsForSelectedItems] firstObject]] == NSOrderedSame) {
            [collectionView deselectItemAtIndexPath:indexPath animated:NO];
        }
        [cell.iconView removeApexOverlay];
    }
    cell.tapHandler = ^(STKSelectionViewCell *tappedCell) {
        [self _selectedCell:[[tappedCell retain] autorelease]];
    };
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section
{
    return (CGSize){20.f, 20.f};
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section
{
    return (UIEdgeInsets){10, 20, 25, 20};
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    STKSelectionHeaderView *view = (STKSelectionHeaderView *)[collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader 
                                                                                                withReuseIdentifier:kHeaderReuseIdentifier
                                                                                                       forIndexPath:indexPath];
    if (indexPath.section == 0) {
        view.headerTitle = (_hasRecommendations ? @"Recommended" : @"All");
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
    [currentSelection.iconView showApexOverlayOfType:STKOverlayTypeEditing];
    [_collectionView selectItemAtIndexPath:currentIndexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
}

@end
