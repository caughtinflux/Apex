#import <UIKit/UIKit.h>

@class SBIcon, SBIconView;
@interface STKSelectionView : UIView <UICollectionViewDelegateFlowLayout, UICollectionViewDataSource>

- (instancetype)initWithFrame:(CGRect)frame selectedIcon:(SBIcon *)selectedIcon centralIcon:(SBIcon *)centralIcon;

@property (nonatomic, copy) NSArray *iconsForSelection;
@property (nonatomic, readonly) SBIcon *selectedIcon; // selectedIcon has to be in iconsForSelection
@property (nonatomic, readonly) UIView *contentView;

@end
