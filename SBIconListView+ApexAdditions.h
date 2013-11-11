#import <SpringBoard/SBIconListView.h>

@interface SBIconListView (ApexAdditions)
- (NSUInteger)stk_visibleIconRowsForCurrentOrientation;
- (NSUInteger)stk_visibleIconColumnsForCurrentOrientation;
- (CGFloat)stk_realVerticalIconPadding;
@end
