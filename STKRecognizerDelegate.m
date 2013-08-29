#import "STKRecognizerDelegate.h"
#import "STKConstants.h"
#import <SpringBoard/SBIconController.h>
#import <objc/runtime.h>

@implementation STKRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return (otherGestureRecognizer == [[objc_getClass("SBIconController") sharedInstance] scrollView].panGestureRecognizer);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
	Class superviewClass = [recognizer.view.superview class];
	if ([superviewClass isKindOfClass:[objc_getClass("SBFolderIconListView") class]] || [superviewClass isKindOfClass:[objc_getClass("SBDockIconListView") class]]) {
		return NO;
	}

	return YES;
}

@end
