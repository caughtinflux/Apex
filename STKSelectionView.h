#import <UIKit/UIKit.h>

@class SBIcon, SBIconView;
@interface STKSelectionView : UIView <UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, UITextFieldDelegate>

- (instancetype)initWithFrame:(CGRect)frame selectedIcon:(SBIcon *)selectedIcon centralIcon:(SBIcon *)centralIcon;

@property (nonatomic, copy) NSArray *iconsForSelection;
@property (nonatomic, readonly) SBIcon *selectedIcon; // selectedIcon has to be in iconsForSelection
@property (nonatomic, readonly) UIView *contentView;
@property (nonatomic, readonly) UITextField *searchTextField;
@property (nonatomic, readonly) UIView *iconCollectionView;

- (void)scrollToSelectedIconAnimated:(BOOL)animated;
- (void)flashScrollIndicators;

@end
