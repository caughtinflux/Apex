#import <SpringBoard/SpringBoard.h>

typedef NS_ENUM(NSInteger, STKOverlayType) {
    STKOverlayTypeEmpty,
    STKOverlayTypeEditing
};

@class STKGroupView;
@interface SBIconView (Apex)

@property (nonatomic, retain) STKGroupView *groupView;
@property (nonatomic, readonly) UIView *apexOverlayView;
@property (nonatomic, readonly) STKGroupView *containerGroupView;

- (void)showApexOverlayOfType:(STKOverlayType)type;
- (void)removeApexOverlay;

@end
