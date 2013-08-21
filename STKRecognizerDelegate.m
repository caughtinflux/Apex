#import "STKRecognizerDelegate.h"
#import "STKConstants.h"
#import <SpringBoard/SBIconController.h>
#import <objc/runtime.h>

@implementation STKRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return (otherGestureRecognizer == [[CLASS("SBIconController") sharedInstance] scrollView].panGestureRecognizer);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
	Class superviewClass = [recognizer.view.superview class];
	if ([superviewClass isKindOfClass:[CLASS("SBFolderIconListView") class]] || [superviewClass isKindOfClass:[CLASS("SBDockIconListView") class]]) {
		return NO;
	}

	return YES;
}

@end
