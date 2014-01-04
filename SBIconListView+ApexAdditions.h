#import <SpringBoard/SBIconListView.h>

@interface SBIconListView (ApexAdditions)
- (NSUInteger)stk_visibleIconRowsForCurrentOrientation;
- (NSUInteger)stk_visibleIconColumnsForCurrentOrientation;
- (CGFloat)stk_realVerticalIconPadding;
- (CGFloat)stk_realHorizontalIconPadding;
- (void)stk_makeIconViewsPerformBlock:(void(^)(SBIconView *iv))block;
@end
