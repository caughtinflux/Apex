#import <Foundation/Foundation.h>

typedef void (^STKAnimatorCompletion)(void);

@class SBIconView, STKSelectionView;
@interface STKGroupSelectionAnimator : NSObject

- (instancetype)initWithSelectionView:(STKSelectionView *)selectionView iconView:(SBIconView *)iconView;

- (void)openSelectionViewAnimatedWithCompletion:(STKAnimatorCompletion)completion;
- (void)closeSelectionViewAnimatedWithCompletion:(STKAnimatorCompletion)completion;

@end
