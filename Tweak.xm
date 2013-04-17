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
static void      STKAddPanRecognizerToIconView(SBIconView *iconView);
// static void      STKAddGestureRecognizerToIcons(NSArray *icons);

#pragma mark - SBIconView Hook
%hook SBIconView
- (void)setIcon:(SBIcon *)icon
{
    %orig();
    UIPanGestureRecognizer *panRecognizer = objc_getAssociatedObject(self, &_panGRKey);
    if ([STKGetStackIconsForIcon(icon) containsObject:[icon leafIdentifier]] || !([self.icon.leafIdentifier isEqualToString:@"com.apple.mobileslideshow"])) {
        // Make sure the recognizer is not added to icons in the stack
        // In the switcher, -setIcon: is called to change the icon, but doesn't change the icon view, make sure the recognizer is removed
        [self removeGestureRecognizer:panRecognizer];
        return;
    }
    if (!panRecognizer) {
        CLog(@"Gesture recognizer doesn't exist, adding...");
        STKAddPanRecognizerToIconView(self);
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stk_editingStateChanged:) name:STKEditingStateChangedNotification object:nil];
}

%new
- (void)stk_panned:(UIPanGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateBegan) {
        if (!_stackManager) {
            _stackManager = [[STKStackManager alloc] initWithCentralIcon:self.icon stackIcons:STKGetStackIconsForIcon(self.icon) interactionHandler:^(SBIconView *tappedIconView) {
                [(SBUIController *)[%c(SBUIController) sharedInstance] launchIcon:tappedIconView.icon];
            }];
            [_stackManager setupView]; 
        }
        _startPoint = [sender locationInView:[[%c(SBIconController) sharedInstance] currentRootIconList]];
    }
    else if (sender.state == UIGestureRecognizerStateChanged) {
        CGPoint point = [sender locationInView:[[%c(SBIconController) sharedInstance] currentRootIconList]];
        CGFloat distance = sqrtf(((point.x - _startPoint.x) * (point.x - _startPoint.x)) + ((point.y - _startPoint.y)  * (point.y - _startPoint.y))); // distance formula
        
        if (distance < _previousDistance) {
            distance = -distance;
        }
        if (_stackManager.isExpanded) {
            distance = -distance;
        }

        _previousDistance = fabsf(distance);
        
        [_stackManager touchesDraggedForDistance:distance];
    }
    if (sender.state == UIGestureRecognizerStateEnded) {
        [_stackManager touchesEnded];
    }
}

%new 
- (void)stk_editingStateChanged:(NSNotification *)notification
{
    BOOL isEditing = [[%c(SBIconController) sharedInstance] isEditing];
    UIPanGestureRecognizer *panRecognizer = objc_getAssociatedObject(self, &_panGRKey);
    if (isEditing && panRecognizer) {
        [self removeGestureRecognizer:panRecognizer];
        objc_setAssociatedObject(self, &_panGRKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    else if (!panRecognizer){
        // Not editing, no recognizer, add ALL the things!
        STKAddPanRecognizerToIconView(self);
    }
}

%end

%hook SBIconController 
- (void)setIsEditing:(BOOL)isEditing
{
    %orig(isEditing);
    [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingStateChangedNotification object:nil];
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

static void STKAddPanRecognizerToIconView(SBIconView *iconView)
{
    UIPanGestureRecognizer *panRecognizer = [[[UIPanGestureRecognizer alloc] initWithTarget:iconView action:@selector(stk_panned:)] autorelease];
    [iconView addGestureRecognizer:panRecognizer];
    objc_setAssociatedObject(iconView, &_panGRKey, panRecognizer, OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        %init();
    }
}
