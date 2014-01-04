#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "STKConstants.h"

typedef NS_ENUM(NSInteger, STKActivationMode) {
	STKActivationModeSwipeUp,
	STKActivationModeSwipeDown,
	STKActivationModeSwipeUpAndDown,
	STKActivationModeDoubleTap
};

@class SBIconView, STKGroup;
@interface STKGroupView : UIView <UIGestureRecognizerDelegate>

- (instancetype)initWithGroup:(STKGroup *)group;

- (void)open;
- (void)close;

@property (nonatomic, readonly) STKGroup *group;
@property (nonatomic, readonly) BOOL isOpen;
@property (nonatomic, assign) STKActivationMode activationMode;

@end
