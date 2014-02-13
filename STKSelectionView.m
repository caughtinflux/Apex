#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKSelectionViewCell.h"
#import <SpringBoard/SpringBoard.h>

#define kCellReuseIdentifier @"STKSelectionViewCell"

@implementation STKSelectionView
{
    UICollectionView *_collectionView;
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
        self.autoresizingMask = _collectionView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        [_collectionView registerClass:[STKSelectionViewCell class] forCellWithReuseIdentifier:kCellReuseIdentifier];

        SBFolderBackgroundView *backgroundView = [[CLASS(SBFolderBackgroundView) alloc] initWithFrame:self.bounds];
        _collectionView.backgroundView = [backgroundView autorelease];

        [self addSubview:_collectionView];
        _delegate = delegate;
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    return [self initWithFrame:frame delegate:nil];
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
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    STKSelectionViewCell *cell = (STKSelectionViewCell *)[_collectionView cellForItemAtIndexPath:indexPath];
    [self.delegate selectionView:self didSelectIconView:cell.iconView];
}

@end
