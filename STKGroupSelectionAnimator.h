#import <Foundation/Foundation.h>

typedef void (^STKAnimatorCompletion)(void);

@class SBIconView, STKSelectionView;
@interface STKGroupSelectionAnimator : NSObject

- (void)openSelectionViewAnimated:(STKSelectionView *)selectionView onIconView:(SBIconView *)iconView withCompletion:(STKAnimatorCompletion)completion;
- (void)closeSelectionViewAnimatedWithCompletion:(STKAnimatorCompletion)completion;

@end
