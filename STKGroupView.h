#import "STKGroup.h"

typedef NS_OPTIONS(NSUInteger, STKActivationMode) {
	STKActivationModeNone	   = 0,
	STKActivationModeSwipeUp   = 1 << 1,
	STKActivationModeSwipeDown = 1 << 2,
	STKActivationModeDoubleTap = 1 << 3
};

#define STKActivationModeIsUpAndDown(_mode) ((_mode & STKActivationModeSwipeUp) && (_mode & STKActivationModeSwipeDown))

@protocol STKGroupViewDelegate;
@class SBIconView, STKGroup;
@interface STKGroupView : UIView <STKGroupObserver, UIGestureRecognizerDelegate>

- (instancetype)initWithGroup:(STKGroup *)group;

@property (nonatomic, retain) STKGroup *group;
@property (nonatomic, assign) STKActivationMode activationMode;
@property (nonatomic, assign) BOOL showPreview;
@property (nonatomic, assign) id<STKGroupViewDelegate> delegate;
@property (nonatomic, assign) BOOL showGrabbers;

@property (nonatomic, readonly) BOOL isOpen;
@property (nonatomic, readonly) BOOL isAnimating;
@property (nonatomic, readonly) STKGroupLayout *subappLayout;
@property (nonatomic, readonly) STKGroupLayout *displacedIconLayout;
@property (nonatomic, readonly) UIView *topGrabberView;
@property (nonatomic, readonly) UIView *bottomGrabberView;

- (void)open;
- (void)openWithCompletionHandler:(void(^)(void))completion;

- (void)close;
- (void)closeWithCompletionHandler:(void(^)(void))completion;

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
