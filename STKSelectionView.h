#import <UIKit/UIKit.h>

@protocol STKSelectionViewDelegate;
@class SBIconView;
@interface STKSelectionView : UIView <UICollectionViewDelegateFlowLayout, UICollectionViewDataSource>

- (instancetype)initWithFrame:(CGRect)frame delegate:(id<STKSelectionViewDelegate>)delegate;

@property (nonatomic, assign) id<STKSelectionViewDelegate> delegate;
@property (nonatomic, copy) NSArray *iconsForSelection;

@end

@protocol STKSelectionViewDelegate <NSObject>
@required
- (void)selectionView:(STKSelectionView *)selectionView didSelectIconView:(SBIconView *)iconView;
@end
