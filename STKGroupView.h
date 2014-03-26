#import "STKGroup.h"

typedef NS_ENUM(NSInteger, STKActivationMode) {
	STKActivationModeSwipeUpAndDown,
	STKActivationModeSwipeUp,
	STKActivationModeSwipeDown,
	STKActivationModeDoubleTap
};

@protocol STKGroupViewDelegate;
@class SBIconView, STKGroup;
@interface STKGroupView : UIView <STKGroupObserver, UIGestureRecognizerDelegate>

- (instancetype)initWithGroup:(STKGroup *)group;

@property (nonatomic, retain) STKGroup *group;
@property (nonatomic, assign) STKActivationMode activationMode;
@property (nonatomic, assign) BOOL showPreview;
@property (nonatomic, assign) id<STKGroupViewDelegate> delegate;

@property (nonatomic, readonly) BOOL isOpen;
@property (nonatomic, readonly) BOOL isAnimating;
@property (nonatomic, readonly) STKGroupLayout *subappLayout;
@property (nonatomic, readonly) STKGroupLayout *displacedIconLayout;

- (void)open;
- (void)close;
- (void)resetLayouts;
- (SBIconView *)subappIconViewForIcon:(SBIcon *)icon;

@end

@protocol STKGroupViewDelegate <SBIconViewDelegate>

@required 
- (BOOL)shouldGroupViewOpen:(STKGroupView *)groupView;
- (BOOL)groupView:(STKGroupView *)groupView shouldRecognizeGesturesSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)recognizer;

@optional
- (void)groupView:(STKGroupView *)groupView didMoveToOffset:(CGFloat)offset;
- (void)groupViewWillOpen:(STKGroupView *)groupView;
- (void)groupViewDidOpen:(STKGroupView *)groupView;
- (void)groupViewWillClose:(STKGroupView *)groupView;
- (void)groupViewDidClose:(STKGroupView *)groupView;
- (void)groupViewWillBeDestroyed:(STKGroupView *)groupView;
@end
