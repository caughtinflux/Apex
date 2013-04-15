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
#import <SpringBoard/SBUIController.h>

#pragma mark - Variables
static char            *_panGRKey;
static STKStackManager *_stackManager;
static CGFloat          _previousDistance;
static CGPoint          _startPoint;

#pragma mark - Function Declarations
// static NSArray * STKIconsWithStack(void);
static NSArray * STKGetStackIconsForIcon(SBIcon *icon);
// static void      STKAddGestureRecognizerToIcons(NSArray *icons);

#pragma mark - SBIconView Hook
%hook SBIconView
- (void)setIcon:(SBIcon *)icon
{
    %orig();
    if ([STKGetStackIconsForIcon(icon) containsObject:[icon leafIdentifier]] || !([self.icon.leafIdentifier isEqualToString:@"com.apple.mobileslideshow"])) {
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
    if ([[%c(SBIconController) sharedInstance] isEditing]) {
        return;     
    }

    if (sender.state == UIGestureRecognizerStateBegan) {
        if (!_stackManager) {
            _stackManager = [[STKStackManager alloc] initWithCentralIcon:self.icon stackIcons:STKGetStackIconsForIcon(self.icon) interactionHandler:^(SBIconView *tappedIconView) {
                [(SBUIController *)[%c(SBUIController) sharedInstance] launchIcon:tappedIconView.icon];
            }];
            [_stackManager setupView];
            _startPoint = [sender locationInView:[[%c(SBIconController) sharedInstance] currentRootIconList]];
        }
    }
    else if (sender.state == UIGestureRecognizerStateChanged) {
        CGPoint point = [sender locationInView:[[%c(SBIconController) sharedInstance] currentRootIconList]];
        CGFloat distance = sqrtf(((point.x - _startPoint.x) * (point.x - _startPoint.x)) + ((point.y - _startPoint.y)  * (point.y - _startPoint.y))); // distance formula
        
        if (distance < _previousDistance) {
            distance = -distance;
        }
        _previousDistance = fabsf(distance);
        
        [_stackManager touchesDraggedForDistance:distance];
    }
    if (sender.state == UIGestureRecognizerStateEnded) {
        [_stackManager touchesEnded];
    }
}

%end


static NSArray * STKGetStackIconsForIcon(SBIcon *icon)
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
