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
#import <SpringBoard/SBApplicationController.h>
#import <SpringBoard/SBApplication.h>


#pragma mark - Declarations
// returns an NSArray of SBIcon object that are in a stack under `icon`.
static NSArray * STKGetStackIconsForIcon(SBIcon *icon);

// Returns an array of bundle IDs
static NSArray * STKGetIconsWithStack(void);

// Creates an STKStackManager object, sets it as an associated object on `iconView`, and returns it.
static STKStackManager * STKSetupManagerForView(SBIconView *iconView);

// Removes the manager from view, closing the stack if it was open
static void STKRemoveManagerFromView(SBIconView *iconView);

static void STKAddPanRecognizerToIconView(SBIconView *iconView);
static void STKRemovePanRecognizerFromIconView(SBIconView *iconView);

static void STKCleanupIconView(SBIconView *iconView);

// Inline Functions, prevent overhead if called too much.
static inline UIPanGestureRecognizer * STKPanRecognizerForView(SBIconView *iconView);
static inline STKStackManager        * STKManagerForView(SBIconView *iconView);

#pragma mark - Direction !
typedef enum {
    STKRecognizerDirectionUp   = 0xf007ba11,
    STKRecognizerDirectionDown = 0x50f7ba11,
    STKRecognizerDirectionNone = 0x0ddba11
} STKRecognizerDirection;
// Returns the direction - top or bottom - for a given velocity
static inline STKRecognizerDirection STKDirectionFromVelocity(CGPoint point);


#pragma mark - SBIconView Hook

%hook SBIconView
- (void)setIcon:(SBIcon *)icon
{
    %orig();

    if ([[%c(SBIconController) sharedInstance] isEditing] || [[%c(SBUIController) sharedInstance] isSwitcherShowing] || !([STKGetIconsWithStack() containsObject:icon.leafIdentifier])) {
        // Make sure the recognizer is not added to icons in the stack
        // In the switcher, -setIcon: is called to change the icon, but doesn't change the icon view, make sure the recognizer is removed
        STKCleanupIconView(self);
        return;
    }

    UIPanGestureRecognizer *panRecognizer = STKPanRecognizerForView(self);
    if (!panRecognizer) {
        STKAddPanRecognizerToIconView(self);
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stk_editingStateChanged:) name:STKEditingStateChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stk_closeStack:) name:STKStackClosingEventNotification object:nil];
}

- (BOOL)canReceiveGrabbedIcon:(SBIconView *)iconView
{
    NSArray *iconsWithStack = STKGetIconsWithStack();
    return ((([iconsWithStack containsObject:self.icon.leafIdentifier]) || ([iconsWithStack containsObject:iconView.icon.leafIdentifier])) ? NO : %orig());
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:STKEditingStateChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:STKStackClosingEventNotification object:nil];
    %orig();
}

#define kBandingFactor  0.1 // The factor by which the distance should be multiplied when the icons have crossed kTargetDistance

static CGPoint                _previousPoint    = CGPointZero;
static CGPoint                _initialPoint     = CGPointZero;
static CGFloat                _previousDistance = 0.0f; // Contains the distance from the initial point.
static STKRecognizerDirection _currentDirection = STKRecognizerDirectionNone; // Stores the direction of the current pan.

%new
- (void)stk_panned:(UIPanGestureRecognizer *)sender
{
    if ([[%c(SBIconController) sharedInstance] isEditing] || !([STKGetIconsWithStack() containsObject:self.icon.leafIdentifier])) {
        STKCleanupIconView(self);
        return;
    }

    SBIconListView *view = [[%c(SBIconController) sharedInstance] currentRootIconList];

    if (sender.state == UIGestureRecognizerStateBegan) {
        STKStackManager *stackManager = STKManagerForView(self);
        if (!stackManager) {
            stackManager = STKSetupManagerForView(self);
        }
        [stackManager setupViewIfNecessary];

        _initialPoint = [sender locationInView:view];
        _currentDirection = STKDirectionFromVelocity([sender velocityInView:view]);
    }

    else if (sender.state == UIGestureRecognizerStateChanged) {
        STKStackManager *stackManager = STKManagerForView(self); // The manager had better exist by this point, or something went horribly wrong

        if (CGPointEqualToPoint(_previousPoint, CGPointZero)) {
            // Make sure previous point is not zero.
            _previousPoint = _initialPoint;
        }

        CGPoint point = [sender locationInView:view];

        BOOL hasCrossedInitial = YES;
        // If the swipe is going beyond the point where it started from, stop the swipe.
        if (_currentDirection == STKRecognizerDirectionUp) {
            hasCrossedInitial = (point.y > _initialPoint.y);
        }
        else if (_currentDirection == STKRecognizerDirectionDown) {
            hasCrossedInitial = (point.y < _initialPoint.y);
        }

        if (hasCrossedInitial) {
            return;
        }

        CGFloat change = sqrtf(((_previousPoint.x - point.x) * (_previousPoint.x - point.x)) + ((_previousPoint.y - point.y)  * (_previousPoint.y - point.y))); // distance from _previousPoint
        CGFloat distance = sqrtf(((_initialPoint.x - point.x) * (_initialPoint.x - point.x)) + ((_initialPoint.y - point.y)  * (_initialPoint.y - point.y))); // distance from original point
        if (distance < _previousDistance || stackManager.isExpanded) {
            // The swipe is going to the opposite direction, so make sure the manager moves its views in the corresponding direction too
            change = -change;
        }

        if ((change > 0) && ((stackManager.currentIconDistance) >= STKGetCurrentTargetDistance())) {
            // Factor this down to simulate elasticity
            // Stack manager allows the icons to go beyond their targets for a little distance
            change *= kBandingFactor;
        }

        [stackManager touchesDraggedForDistance:change];

        _previousPoint = point;
        _previousDistance = fabsf(distance);
    }

    else if (sender.state == UIGestureRecognizerStateEnded) {
        [STKManagerForView(self) touchesEnded];

        // Reset the static vars
        _previousPoint = CGPointZero;
        _initialPoint = CGPointZero;
        _previousDistance = 0.f;
        _currentDirection = STKRecognizerDirectionNone;
    }
}

%new 
- (void)stk_editingStateChanged:(NSNotification *)notification
{
    BOOL isEditing = [[%c(SBIconController) sharedInstance] isEditing];
    
    if (isEditing) {
        STKCleanupIconView(self);
    }
    else {
        STKAddPanRecognizerToIconView(self);
    }
}

%new 
- (void)stk_closeStack:(id)notification
{
    STKStackManager *manager = STKManagerForView(self);
    [manager closeStackWithCompletionHandler:^{
        STKRemoveManagerFromView(self);
    }];
}

%end

%hook SBIconController
- (void)setIsEditing:(BOOL)isEditing
{
    %orig(isEditing);
    [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingStateChangedNotification object:nil];
}

/*  
    IMPORTENTE:
        Various hooks to intercept events that should make the stack close
*/
- (void)iconWasTapped:(SBIcon *)icon
{
    if ([STKGetIconsWithStack() containsObject:icon.leafIdentifier]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:STKStackClosingEventNotification object:nil];
    }
    
    %orig();
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    %orig();
    [[NSNotificationCenter defaultCenter] postNotificationName:STKStackClosingEventNotification object:nil];
}

%end

%hook SBUIController
- (BOOL)clickedMenuButton
{
    if ([STKStackManager anyStackOpen] || [STKStackManager anyStackInMotion]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:STKStackClosingEventNotification object:nil];
        return NO;// OOoooooooooooo
    }
    else {
        return %orig();
    }
}

- (BOOL)_activateSwitcher:(NSTimeInterval)animationDuration
{
    [[NSNotificationCenter defaultCenter] postNotificationName:STKStackClosingEventNotification object:nil];
    return %orig(animationDuration);
}

%end

#pragma mark - Associated Object Keys
static char *_panGRKey;
static char *_stackManagerKey;

#pragma mark - Static Function Definitions
static NSArray * STKGetIconsWithStack(void)
{
    return @[@"com.apple.mobileslideshow"];
}

static NSArray * STKGetStackIconsForIcon(SBIcon *icon)
{
    SBIconModel *model = (SBIconModel *)[[%c(SBIconController) sharedInstance] model];
    if ([icon.leafIdentifier isEqual:@"com.apple.mobileslideshow"]) {
        return @[[model applicationIconForDisplayIdentifier:@"com.apple.mobiletimer"],
                 [model applicationIconForDisplayIdentifier:@"com.apple.mobilenotes"],
                 [model applicationIconForDisplayIdentifier:@"com.apple.reminders"],
                 [model applicationIconForDisplayIdentifier:@"com.apple.mobilecal"]
                ];
    }

    return nil;
}

static void STKAddPanRecognizerToIconView(SBIconView *iconView)
{
    UIPanGestureRecognizer *panRecognizer = objc_getAssociatedObject(iconView, &_panGRKey);
    // Don't add a recognizer if it already exists
    if (!panRecognizer) {
        panRecognizer = [[[UIPanGestureRecognizer alloc] initWithTarget:iconView action:@selector(stk_panned:)] autorelease];
        [iconView addGestureRecognizer:panRecognizer];
        objc_setAssociatedObject(iconView, &_panGRKey, panRecognizer, OBJC_ASSOCIATION_ASSIGN);
    }
}

static void STKRemovePanRecognizerFromIconView(SBIconView *iconView)
{
    UIPanGestureRecognizer *recognizer = STKPanRecognizerForView(iconView);
    [iconView removeGestureRecognizer:recognizer];
    objc_setAssociatedObject(iconView, &_panGRKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static STKStackManager * STKSetupManagerForView(SBIconView *iconView)
{
    STKStackManager *stackManager = nil;
    stackManager = [[STKStackManager alloc] initWithCentralIcon:iconView.icon stackIcons:STKGetStackIconsForIcon(iconView.icon)];
    stackManager.interactionHandler = \
        ^(SBIconView *tappedIconView) {
            if (tappedIconView) {
                [stackManager closeStackSettingCentralIcon:tappedIconView.icon completion:^{
                    SBApplication *tappedApp = [[%c(SBApplicationController) sharedInstance] applicationWithDisplayIdentifier:tappedIconView.icon.leafIdentifier];
                    [(SBUIController *)[%c(SBUIController) sharedInstance] activateApplicationFromSwitcher:tappedApp];
                    STKRemoveManagerFromView(iconView);
                }];
            }
            else {
                STKRemoveManagerFromView(iconView);
            }
        };

    objc_setAssociatedObject(iconView, &_stackManagerKey, stackManager, OBJC_ASSOCIATION_RETAIN);
    [stackManager release];

    return stackManager;
}

static void STKRemoveManagerFromView(SBIconView *iconView)
{
    STKStackManager *manager = STKManagerForView(iconView);
    if (manager.isExpanded) {
        [manager closeStack];   
    }
    objc_setAssociatedObject(iconView, &_stackManagerKey, nil, OBJC_ASSOCIATION_RETAIN);
}

static void STKCleanupIconView(SBIconView *iconView)
{
    STKRemovePanRecognizerFromIconView(iconView);
    STKRemoveManagerFromView(iconView); // Remove the manager irrespective of whether the view exists or not
}

#pragma mark - Inliner Definitions
static inline STKRecognizerDirection STKDirectionFromVelocity(CGPoint point)
{
    if (point.y == 0) {
        return STKRecognizerDirectionNone;
    }

    return ((point.y < 0) ? STKRecognizerDirectionUp : STKRecognizerDirectionDown);
}

static inline UIPanGestureRecognizer * STKPanRecognizerForView(SBIconView *iconView)
{
    return objc_getAssociatedObject(iconView, &_panGRKey);
}

static inline STKStackManager * STKManagerForView(SBIconView *iconView)
{
    return objc_getAssociatedObject(iconView, &_stackManagerKey);
}

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        %init();
    }
}
