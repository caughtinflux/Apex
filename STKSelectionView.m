#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKSelectionViewCell.h"
#import <SpringBoard/SpringBoard.h>

#define kCellReuseIdentifier @"STKSelectionViewCell"

@implementation STKSelectionView
{
    UICollectionView *_collectionView;
    SBFolderBackgroundView *_backgroundView;
    SBIcon *_selectedIcon;
    SBIcon *_centralIcon;
    SBIconView *_selectedIconView;
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
        _collectionView.contentInset = UIEdgeInsetsMake(20, 20, 20, 20);
        _collectionView.layer.cornerRadius = 35.f; // the default corner radius for folders, apparently.
        _collectionView.layer.masksToBounds = YES;
        _collectionView.allowsSelection = YES;
        _collectionView.contentInset = (UIEdgeInsets){10.f, 0.f, 0.f, 0.f};
        _collectionView.scrollIndicatorInsets = (UIEdgeInsets){25.f, 0.f, 25.f, 0.f};
        self.autoresizingMask = _collectionView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        [_collectionView registerClass:[STKSelectionViewCell class] forCellWithReuseIdentifier:kCellReuseIdentifier];

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
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"displayName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    _iconsForSelection = [[icons sortedArrayUsingDescriptors:@[sortDescriptor]] retain];
    [_collectionView reloadData];
}

- (void)flashScrollIndicators
{
    [_collectionView flashScrollIndicators];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.iconsForSelection.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    STKSelectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCellReuseIdentifier forIndexPath:indexPath];
    cell.iconView.icon = self.iconsForSelection[indexPath.item];
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
