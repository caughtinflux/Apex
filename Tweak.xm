#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "STKStackManager.h"

#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIcon.h>
#import <SpringBoard/SBApplicationIcon.h>
#import <SpringBoard/SBIconModel.h>
#import <SpringBoard/SBIconViewMap.h>
#import <SpringBoard/SBIconView.h>
#import <SpringBoard/SBIconListView.h>
#import <SpringBoard/SBDockIconListView.h>

#pragma mark - Variables
static char            *_panGRKey;
static STKStackManager *_stackManager;
static CGFloat          _previousVelocity;

#pragma mark - Function Declarations
static NSArray * STKGetStackIcons(void);

#pragma mark - SBIconView Hook
%hook SBIconView
- (void)setIcon:(SBIcon *)icon
{
    %orig();
    if ([STKGetStackIcons() containsObject:[icon leafIdentifier]]) {
        // Make sure the recognizer is not added to icons in the stack;
        return;
    }
    UIPanGestureRecognizer *panRecognizer = objc_getAssociatedObject(self, &_panGRKey);
    if (!panRecognizer) {
        panRecognizer = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(stk_panned:)] autorelease];
        [self addGestureRecognizer:panRecognizer];
        objc_setAssociatedObject(self, &_panGRKey, panRecognizer, OBJC_ASSOCIATION_ASSIGN);
    }
}

%new
- (void)stk_panned:(UIPanGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateBegan) {
        if (!_stackManager) {
            _stackManager = [[STKStackManager alloc] initWithCentralIcon:self.icon stackIcons:STKGetStackIcons()];
            [_stackManager setupView];
        }
    }
    if (sender.state == UIGestureRecognizerStateChanged) {
        CGPoint point = [sender locationInView:[[%c(SBIconController) sharedInstance] currentRootIconList]];
        CGFloat distance = sqrtf(((point.x - self.center.x) * (point.x - self.center.x)) + ((point.y - self.center.y)  * (point.y - self.center.y))); // distance formula
        
        CGPoint velocity = [gestureRecognizer velocityInView:[[%c(SBIconController) sharedInstance] currentRootIconList]];
        if (!(((velocity.x * _previousVelocity.x) + (velocity.y * _previousVelocity.y)) > 0)) {
            // Current pan is in a direction opposite to last, invert distance...
            distance = -distance;
        }
        _previousVelocity = velocity;

        CLog(@"Distance: %.2f", distance);
        [_stackManager touchesDraggedForDistance:distance];
    }
    if (sender.state == UIGestureRecognizerStateEnded) {

    }
}

%end

static NSArray * STKGetStackIcons(void)
{
    SBIconModel *model = (SBIconModel *)[[%c(SBIconController) sharedInstance] model];
    return @[[model applicationIconForDisplayIdentifier:@"com.apple.mobiletimer"],
             [model applicationIconForDisplayIdentifier:@"com.apple.mobilecal"],
             [model applicationIconForDisplayIdentifier:@"com.apple.reminders"],
             [model applicationIconForDisplayIdentifier:@"com.apple.mobilenotes"]];
}

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        %init();
    }
}
