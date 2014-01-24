#import <SpringBoard/SpringBoard.h>
#import "STKIconOverlayView.h"

@class STKGroupView;
@interface SBIconView (Apex)

- (void)setGroupView:(STKGroupView *)view;
- (void)removeGroupView;
- (STKGroupView *)groupView;

- (void)setApexOverlayView:(STKIconOverlayView *)overlayView;
- (STKIconOverlayView *)apexOverlayView;

@end
