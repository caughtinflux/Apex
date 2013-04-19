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


#pragma mark - Declarations
static char *_panGRKey;
static char *_stackManagerKey;

static CGFloat _previousDistance;
static CGPoint _startPoint;
static BOOL    _previousEditingState;

// returns an NSArray of SBIcon object that are in a stack under `icon`.
static NSArray * STKGetStackIconsForIcon(SBIcon *icon);

// Returns an array of bundle IDs
static NSArray * STKGetIconsWithStack(void);

// Creates an STKStackManager object, sets it as an associated object on `iconView`, and returns it.
static STKStackManager * STKSetupManagerForView(SBIconView *iconView);

static void STKAddPanRecognizerToIconView(SBIconView *iconView);
static void STKRemovePanRecognizerFromIconView(SBIconView *iconView);

// Inline Functions,  prevents function overhead if called too much.
static inline UIPanGestureRecognizer * STKGetGestureRecognizerForView(SBIconView *iconView);
static inline STKStackManager        * STKManagerForView(SBIconView *iconView);
static inline void                     STKRemoveManagerFromView(SBIconView *iconView);


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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stk_homescreenWillScroll:) name:STKHomescreenWillScrollNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:STKEditingStateChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:STKHomescreenWillScrollNotification object:nil];

    %orig();
}

%new
- (void)stk_panned:(UIPanGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateBegan) {
        STKStackManager *stackManager = STKManagerForView(self);
        if (!stackManager) {
            stackManager = STKSetupManagerForView(self);
        }
        [stackManager setupViewIfNecessary];
        _startPoint = [sender locationInView:[[%c(SBIconController) sharedInstance] currentRootIconList]];
    }

    else if (sender.state == UIGestureRecognizerStateChanged) {
        STKStackManager *stackManager = STKManagerForView(self); // The manager had better exist by this point, or something went horribly wrong

        CGPoint point = [sender locationInView:[[%c(SBIconController) sharedInstance] currentRootIconList]];
        CGFloat distance = sqrtf(((point.x - _startPoint.x) * (point.x - _startPoint.x)) + ((point.y - _startPoint.y)  * (point.y - _startPoint.y))); // distance formula
        CLog(@"Y distance: %.2f", fabsf(point.y - _startPoint.y));
        CLog(@"from formula: %.2f", distance);
        if (distance < _previousDistance) {
            distance = -distance;
        }
        if (stackManager.isExpanded) {
            distance = -distance;
        }

        _previousDistance = fabsf(distance);
        
        [stackManager touchesDraggedForDistance:distance];
    }

    else if (sender.state == UIGestureRecognizerStateEnded) {
        STKStackManager *manager = STKManagerForView(self);
        [manager touchesEnded];
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
        STKAddPanRecognizerToIconView(self);
    }
    STKRemoveManagerFromView(self); // Remove the manager irrespective of whether the view exists or not
}

%new 
- (void)stk_homescreenWillScroll:(NSNotification *)notification
{
    STKStackManager *manager = STKManagerForView(self);
    if (manager.isExpanded) {
        [manager closeStack];   
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

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    %orig();
    [[NSNotificationCenter defaultCenter] postNotificationName:STKHomescreenWillScrollNotification object:nil];
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

static STKStackManager * STKSetupManagerForView(SBIconView *iconView)
{
    DLog(@"");
    STKStackManager *stackManager = nil;
    stackManager = [[STKStackManager alloc] initWithCentralIcon:iconView.icon stackIcons:STKGetStackIconsForIcon(iconView.icon)];
    stackManager.interactionHandler = ^(SBIconView *tappedIconView) { 
                                            [stackManager closeStackSettingCentralIcon:tappedIconView.icon completion:^{
                                                [(SBUIController *)[%c(SBUIController) sharedInstance] launchIcon:tappedIconView.icon];
                                            }];
                                        };
    objc_setAssociatedObject(iconView, &_stackManagerKey, stackManager, OBJC_ASSOCIATION_RETAIN);
    [stackManager release];

    return stackManager;
}


#pragma mark - Inliner Definitions
static inline UIPanGestureRecognizer * STKGetGestureRecognizerForView(SBIconView *iconView)
{
    return objc_getAssociatedObject(iconView, &_panGRKey);
}

static inline STKStackManager * STKManagerForView(SBIconView *iconView)
{
    return objc_getAssociatedObject(iconView, &_stackManagerKey);
}

static inline void STKRemoveManagerFromView(SBIconView *iconView)
{
    objc_setAssociatedObject(iconView, &_stackManagerKey, nil, OBJC_ASSOCIATION_RETAIN);
}

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        %init();
    }
}
