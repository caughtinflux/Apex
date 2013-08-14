#import "STKRecognizerDelegate.h"
#import "STKConstants.h"
#import <SpringBoard/SBIconController.h>
#import <objc/runtime.h>

@implementation STKRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return (otherGestureRecognizer == [[objc_getClass("SBIconController") sharedInstance] scrollView].panGestureRecognizer);
}

@end
