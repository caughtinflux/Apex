#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKSelectionViewCell.h"
#import <SpringBoard/SpringBoard.h>

#define kCellReuseIdentifier @"STKSelectionViewCell"

@implementation STKSelectionView
{
    UICollectionView *_collectionView;
    SBFolderBackgroundView *_backgroundView;
}

- (instancetype)initWithFrame:(CGRect)frame delegate:(id<STKSelectionViewDelegate>)delegate;
{   
    if ((self = [super initWithFrame:frame])) {
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
        self.autoresizingMask = _collectionView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        [_collectionView registerClass:[STKSelectionViewCell class] forCellWithReuseIdentifier:kCellReuseIdentifier];

        _backgroundView = [[CLASS(SBFolderBackgroundView) alloc] initWithFrame:self.bounds];
        [self addSubview:_backgroundView];
        _collectionView.backgroundView = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];

        [self addSubview:_collectionView];
        _delegate = delegate;
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    return [self initWithFrame:frame delegate:nil];
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
    [_collectionView reloadData];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.iconsForSelection.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    STKSelectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCellReuseIdentifier forIndexPath:indexPath];
    cell.iconView.icon = self.iconsForSelection[indexPath.item];
    cell.tapHandler = ^(STKSelectionViewCell *tappedCell) {
        [self _selectedCell:[[tappedCell retain] autorelease]];
    };
    return cell;
}

- (void)_selectedCell:(STKSelectionViewCell *)cell
{
    [self.delegate selectionView:self didSelectIconView:cell.iconView];
}

@end
