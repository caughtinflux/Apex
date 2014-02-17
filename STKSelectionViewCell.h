#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

typedef void (^STKSelectionViewCellTapHandler)(id cell);

@interface STKSelectionViewCell : UICollectionViewCell <SBIconViewDelegate>
@property (nonatomic, readonly) SBIconView *iconView;
@property (nonatomic, copy) STKSelectionViewCellTapHandler tapHandler;
@end
