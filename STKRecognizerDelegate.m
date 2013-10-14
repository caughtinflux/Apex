#import "STKRecognizerDelegate.h"
#import "STKConstants.h"
#import <SpringBoard/SBIconController.h>
#import <objc/runtime.h>

@implementation STKRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return ((otherGestureRecognizer == [[objc_getClass("SBIconController") sharedInstance] scrollView].panGestureRecognizer) ||
            ([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]] && [otherGestureRecognizer.view.superview isKindOfClass:objc_getClass("FEGridFolderView")]));

}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
    Class superviewClass = [recognizer.view.superview class];
    if ([superviewClass isKindOfClass:[objc_getClass("SBDockIconListView") class]]) {
        return NO;
    }

    return YES;
}

@end
