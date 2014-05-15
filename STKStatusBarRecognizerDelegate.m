#import "STKStatusBarRecognizerDelegate.h"
#import "STKConstants.h"

@implementation STKStatusBarRecognizerDelegate
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    return ![(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}
@end
