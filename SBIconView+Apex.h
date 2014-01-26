#import <SpringBoard/SpringBoard.h>
#import "STKIconOverlayView.h"

@class STKGroupView;
@interface SBIconView (Apex)

- (void)setGroupView:(STKGroupView *)view;
- (void)removeGroupView;
// Returns the group view owned by the receiver
- (STKGroupView *)groupView;

// Returns group view the receiver is contained in, if any
- (STKGroupView *)containerGroupView;

- (void)setApexOverlayView:(STKIconOverlayView *)overlayView;
- (STKIconOverlayView *)apexOverlayView;

@end
