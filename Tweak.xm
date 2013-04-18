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
#import <SpringBoard/SBIconImageView.h>
#import <SpringBoard/SBIconListView.h>
#import <SpringBoard/SBDockIconListView.h>
#import <SpringBoard/SBUIController.h>

#pragma mark - Variables
static char            *_panGRKey;
static char            *_stackManagerKey;
static STKStackManager *_stackManager;
static CGFloat          _previousDistance;
static CGPoint          _startPoint;
static BOOL             _previousEditingState;

#pragma mark - Function Declarations
// returns an NSArray of SBIcon object that are in a stack under `icon`.
static NSArray * STKGetStackIconsForIcon(SBIcon *icon);

// Returns an array of bundle IDs
static NSArray * STKGetIconsWithStack(void);

static void      STKAddPanRecognizerToIconView(SBIconView *iconView);
static void      STKRemovePanRecognizerFromIconView(SBIconView *iconView);

// Inline Functions,  prevent function overhead if called too much.
static inline UIPanGestureRecognizer * STKGetGestureRecognizerForView(SBIconView *iconView);
static inline STKStackManager        * STKGetStackManagerForView(SBIconView *iconView);

#pragma mark - SBIconView Hook
%hook SBIconView
- (void)setIcon:(SBIcon *)icon
{
    %orig();
    UIPanGestureRecognizer *panRecognizer = STKGetGestureRecognizerForView(self);
    if (!([STKGetIconsWithStack() containsObject:icon.leafIdentifier])) {
        // Make sure the recognizer is not added to icons in the stack
        // In the switcher, -setIcon: is called to change the icon, but doesn't change the icon view, make sure the recognizer is removed
        if (panRecognizer) {
            STKRemovePanRecognizerFromIconView(self);
        }
        return;
    }
    if (!panRecognizer) {
        CLog(@"Gesture recognizer doesn't exist for icon: %@, adding", icon.leafIdentifier);
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
                [_stackManager closeStackSettingCentralIcon:tappedIconView.icon completion:^{
                    [(SBUIController *)[%c(SBUIController) sharedInstance] launchIcon:tappedIconView.icon];
                }];
            }];
        }
        [_stackManager setupViewIfNecessary];
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
    UIPanGestureRecognizer *panRecognizer = STKGetGestureRecognizerForView(self);
    if (isEditing && panRecognizer) {
        STKRemovePanRecognizerFromIconView(self);
    }
    else if (!panRecognizer) {
        // Not editing, no recognizer, add ALL the things!
        [_stackManager recalculateLayoutsWithStackIcons:STKGetStackIconsForIcon(self.icon)];
        STKAddPanRecognizerToIconView(self);
    }
}

%end

%hook SBIconController 
- (void)setIsEditing:(BOOL)isEditing
{
    %orig(isEditing);
    if (_previousEditingState == isEditing) {
        // This method is called virtually every time you touch SpringBoard, don't do shit unecessarily
        return;
    }
    _previousEditingState = isEditing;
    [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingStateChangedNotification object:nil];
}
%end

#pragma mark - Static Function Definitions
static NSArray * STKGetIconsWithStack(void)
{
    return @[@"com.apple.mobileslideshow"];
}

static NSArray * STKGetStackIconsForIcon(SBIcon *icon)
{
    SBIconModel *model = (SBIconModel *)[[%c(SBIconController) sharedInstance] model];
    return @[[model applicationIconForDisplayIdentifier:@"com.apple.mobiletimer"],
             [model applicationIconForDisplayIdentifier:@"com.apple.mobilenotes"],
             [model applicationIconForDisplayIdentifier:@"com.apple.reminders"],
             [model applicationIconForDisplayIdentifier:@"com.apple.mobilecal"]];
}

static void STKAddPanRecognizerToIconView(SBIconView *iconView)
{
    DLog(@"");
    UIPanGestureRecognizer *panRecognizer = [[[UIPanGestureRecognizer alloc] initWithTarget:iconView action:@selector(stk_panned:)] autorelease];
    [iconView addGestureRecognizer:panRecognizer];
    objc_setAssociatedObject(iconView, &_panGRKey, panRecognizer, OBJC_ASSOCIATION_ASSIGN);
}

static void STKRemovePanRecognizerFromIconView(SBIconView *iconView)
{
    DLog(@"");
    UIPanGestureRecognizer *recognizer = STKGetGestureRecognizerForView(iconView);
    [iconView removeGestureRecognizer:recognizer];
    objc_setAssociatedObject(iconView, &_panGRKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - Inliners Definitions
static inline UIPanGestureRecognizer * STKGetGestureRecognizerForView(SBIconView *iconView)
{
    return objc_getAssociatedObject(iconView, &_panGRKey);
}

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        %init();
    }
}
