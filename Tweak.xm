#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "STKConstants.h"
#import "STKStackManager.h"
#import "STKRecognizerDelegate.h"
#import "STKPreferences.h"

#import <SpringBoard/SpringBoard.h>
#import <objc/message.h>
#import <notify.h>

#pragma mark - Function Declarations

static STKStackManager * STKSetupManagerForView(SBIconView *iconView); // Creates an STKStackManager object, sets it as an associated object on `iconView`, and returns it.
static void STKRemoveManagerFromView(SBIconView *iconView); // Removes the manager from view, closing the stack if it was open
static void STKAddPanRecognizerToIconView(SBIconView *iconView);
static void STKRemovePanRecognizerFromIconView(SBIconView *iconView);


static inline void STKSetupIconView(SBIconView *iconView); // Adds recogniser and sets up stack manager for the preview
static inline void STKCleanupIconView(SBIconView *iconView); // Removes recogniser and stack manager



// Inline Functions, prevent overhead if called too much.
static inline UIPanGestureRecognizer * STKPanRecognizerForView(SBIconView *iconView);
static inline        STKStackManager * STKManagerForView(SBIconView *iconView);
static inline               NSString * STKGetLayoutPathForIcon(SBIcon *icon);

static inline            void   STKSetActiveManager(STKStackManager *manager);
static inline STKStackManager * STKGetActiveManager(void);
static inline            void   STKCloseActiveManager(void);


#pragma mark - Direction !
typedef enum {
    STKRecognizerDirectionUp   = 0xf007ba11,
    STKRecognizerDirectionDown = 0x50f7ba11,
    STKRecognizerDirectionNone = 0x0ddba11
} STKRecognizerDirection;

// Returns the direction - top or bottom - for a given velocity
static inline STKRecognizerDirection STKDirectionFromVelocity(CGPoint point);


/////////////////////////////////////////////////////////////////////////
///////////////// STATIC VARIABLES /////////////////////////////////////
///////////////////////////////////////////////////////////////////////
static BOOL _wantsSafeIconViewRetrieval;
static BOOL _switcherIsVisible;
///////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////




////////////////////////////////////////////////////////////////////
///////////////////// REAL SHIT STARTS ////////////////////////////
//////////////////////////////////////////////////////////////////

%hook SBIconViewMap
- (void)iconViewDidChangeLocation:(SBIconView *)iconView
{
    if (iconView.location != SBIconViewLocationHomeScreen) {
        // If the icon is going intp a folder
        STKCleanupIconView(iconView);
    }

    // All the icons' manager will need to re-calculate layouts if any one icon moves.
    [[NSNotificationCenter defaultCenter] postNotificationName:STKRecalculateLayoutsNotification object:nil userInfo:nil];
}

%new
- (SBIconView *)safeIconViewForIcon:(SBIcon *)icon
{
    _wantsSafeIconViewRetrieval = YES;

    SBIconView *iconView = [self iconViewForIcon:icon];
    
    _wantsSafeIconViewRetrieval = NO;

    return iconView;
}
%end

#pragma mark - SBIconView Hook
%hook SBIconView

- (void)setIcon:(SBIcon *)icon
{    
    %orig(icon);

    if (!icon ||
        _wantsSafeIconViewRetrieval || 
        self.location != SBIconViewLocationHomeScreen || [self.superview isKindOfClass:%c(SBFolderIconListView)] ||
        ![icon isLeafIcon] ||
        [[STKPreferences sharedPreferences] iconIsInStack:icon]) {
        // Safe icon retrieval is just a way to be sure setIcon: calls from inside -[SBIconViewMap iconViewForIcon:] aren't intercepted here, causing an infinite loop
        // Make sure the recognizer is not added to icons in the stack
        // In the switcher, -setIcon: is called to change the icon, but doesn't change the icon view, make sure the recognizer is removed
        STKCleanupIconView(self);
        return;
    }

    // Add self to the homescreen map, since _cmd is sometimes called before the map is configured completely.
    if ([[%c(SBIconViewMap) homescreenMap] mappedIconViewForIcon:icon] == nil) {
        [[%c(SBIconViewMap) homescreenMap] _addIconView:self forIcon:icon];
    }

    STKSetupIconView(self);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stk_editingStateChanged:) name:STKEditingStateChangedNotification object:nil];
}

- (BOOL)canReceiveGrabbedIcon:(SBIconView *)iconView
{
    return ((ICON_HAS_STACK(self.icon) || ICON_HAS_STACK(iconView.icon)) ? NO : %orig());
}

- (void)dealloc
{
    // Remove each registered notification individually, so we don't conflict with other tweaks.
    [[NSNotificationCenter defaultCenter] removeObserver:self name:STKEditingStateChangedNotification object:nil];

    %orig();
}

#define kBandingFactor  0.15 // The factor by which the distance should be multiplied to simulate the rubber banding effect

static CGPoint                _previousPoint    = CGPointZero;
static CGPoint                _initialPoint     = CGPointZero;
static CGFloat                _previousDistance = 0.0f; // Contains the distance from the initial point.
static STKRecognizerDirection _currentDirection = STKRecognizerDirectionNone; // Stores the direction of the current pan.

%new
- (void)stk_panned:(UIPanGestureRecognizer *)sender
{
    UIView *view = [STKListViewForIcon(self.icon) superview];
    STKStackManager *stackManager = STKManagerForView(self);
    STKStackManager *activeManager = STKGetActiveManager();

    if ([[%c(SBIconController) sharedInstance] hasOpenFolder] || stackManager.isExpanded || (activeManager != nil && activeManager != stackManager) || ([self.superview isKindOfClass:%c(SBFolderIconListView)])) {
        return;
    }

    if (sender.state == UIGestureRecognizerStateBegan) {
        if (self.location == SBIconViewLocationSwitcher || [[%c(SBIconController) sharedInstance] isEditing]) {
            // Preliminary check
            STKCleanupIconView(self);
            return;
        }

        CGPoint translation = [sender translationInView:view];
        if (!((fabsf(translation.x / translation.y) < 5.0) || translation.x == 0)) {
            return;
        }
            
        // Turn off scrolling if it's s vertical swipe
        [[%c(SBIconController) sharedInstance] scrollView].scrollEnabled = NO;

        // Update the target distance based on icons positions when the pan begins
        // This way, we can be sure that the icons are indeed in the required location 
        STKUpdateTargetDistanceInListView(STKListViewForIcon(self.icon));
        [stackManager setupViewIfNecessary];

        _initialPoint = [sender locationInView:view];
        _currentDirection = STKDirectionFromVelocity([sender velocityInView:view]);
        _previousPoint = _initialPoint; // Previous point is also initial at the start :P


        STKSetActiveManager(stackManager);
        [stackManager touchesBegan];
    }

    else if (sender.state == UIGestureRecognizerStateChanged) {
        if ([[%c(SBIconController) sharedInstance] scrollView].isDragging) {
            return;
        }

        CGPoint point = [sender locationInView:view];

        // If the swipe is going beyond the point where it started from, stop the swipe.
        if (((_currentDirection == STKRecognizerDirectionUp) && (point.y > _initialPoint.y)) || ((_currentDirection == STKRecognizerDirectionDown) && (point.y < _initialPoint.y))) {
            point = _initialPoint;
        }

        CGFloat change = fabsf(_previousPoint.y - point.y); // Vertical
        CGFloat distance = fabsf(_initialPoint.y - point.y);
        
        if (distance < _previousDistance) {
            // The swipe is going to the opposite direction, so make sure the manager moves its views in the corresponding direction too
            change = -change;
        }


        if ((change > 0) && (stackManager.currentIconDistance >= STKGetCurrentTargetDistance())) {
            // Factor this down to simulate elasticity when the icons have reached their target locations
            // Stack manager allows the icons to go beyond their targets for a little distance
            change *= kBandingFactor;
        }

        [stackManager touchesDraggedForDistance:change];

        _previousPoint = point;
        _previousDistance = fabsf(distance);
    }

    else {
        [stackManager touchesEnded];

        // Reset the static vars
        _previousPoint = CGPointZero;
        _initialPoint = CGPointZero;
        _previousDistance = 0.f;
        _currentDirection = STKRecognizerDirectionNone;

        if (stackManager.isExpanded) {
            STKSetActiveManager(stackManager);
        }
        else {
            // The stack has closed, no manager is active no.
            STKSetActiveManager(nil);
        }

        [[%c(SBIconController) sharedInstance] scrollView].scrollEnabled = YES;
    }
}

%new 
- (void)stk_editingStateChanged:(NSNotification *)notification
{   
    BOOL isEditing = [[%c(SBIconController) sharedInstance] isEditing];
    
    if (isEditing) {
        STKRemovePanRecognizerFromIconView(self);
    }
    else {
        STKAddPanRecognizerToIconView(self);
    }
}

%new 
- (void)stk_closeStack:(NSNotification *)notification
{
    if (STKManagerForView(self).isExpanded) {
        [STKManagerForView(self) closeStack];
        STKSetActiveManager(nil);
    }
}

/*      __  _____   _  ___  __
       / / / /   | | |/ / |/ /
      / /_/ / /| | |   /|   / 
     / __  / ___ |/   |/   |  
    /_/ /_/_/  |_/_/|_/_/|_|  
*/

%new
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    STKStackManager *activeManager = STKGetActiveManager();
    
    if ((activeManager != nil) && (STKManagerForView(self) == activeManager)) {
        // Only if `self`'s manager is the active manager should we bother forwarding touches.
        UIView *view = [activeManager hitTest:point withEvent:event];
        if (view) {
            return view;
        }    
    }

    IMP hitTestIMP = class_getMethodImplementation([UIView class], _cmd);
    return hitTestIMP(self, _cmd, point, event);
}

%end


#pragma mark - SBIconController Hook
%hook SBIconController
- (void)setIsEditing:(BOOL)isEditing
{
    %orig(isEditing);
    [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingStateChangedNotification object:nil];
}

// Ghost all the other stacks' sub-apps when the list view is being ghosted
- (void)setCurrentPageIconsPartialGhostly:(CGFloat)value forRequester:(NSInteger)requester skipIcon:(SBIcon *)icon
{
    %orig(value, requester, icon);

    STKStackManager *activeManager = STKGetActiveManager();
    SBIconListView *listView = [[%c(SBIconController) sharedInstance] currentRootIconList];
    
    __block BOOL passedCentralIcon = NO;

    [listView makeIconViewsPerformBlock:^(SBIconView *iconView) {
        // Only check if the icon's ID matches the active manager's central icon if it hasn't been checked and found already
        if (passedCentralIcon == NO && [iconView.icon.leafIdentifier isEqualToString:activeManager.centralIcon.leafIdentifier]) {
            passedCentralIcon = YES;
            return;
        }

        STKStackManager *iconViewManager = STKManagerForView(iconView);
        [iconViewManager setStackIconAlpha:value];
    }];
}

- (void)setCurrentPageIconsGhostly:(BOOL)shouldGhost forRequester:(NSInteger)requester skipIcon:(SBIcon *)icon
{
    %orig(shouldGhost, requester, icon);

    STKStackManager *activeManager = STKGetActiveManager();
    SBIconListView *listView = [[%c(SBIconController) sharedInstance] currentRootIconList];

    __block BOOL passedCentralIcon = NO;

    [listView makeIconViewsPerformBlock:^(SBIconView *iconView) {
        if (passedCentralIcon == NO && [iconView.icon.leafIdentifier isEqualToString:activeManager.centralIcon.leafIdentifier]) {
            passedCentralIcon = YES;
            return;
        }

        STKStackManager *iconViewManager = STKManagerForView(iconView);
        [iconViewManager setStackIconAlpha:((shouldGhost && [iconView isGhostly]) ? 0.0 : 1.0)];
    }];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    %orig(scrollView);
    STKCloseActiveManager();
}
%end

/**************************************************************************************************************************/
/****************************************************** Icon Hiding *******************************************************/
#pragma mark - SBIconModel Hook
%hook SBIconModel
- (BOOL)isIconVisible:(SBIcon *)icon
{
    BOOL isVisible = %orig();
    if (_switcherIsVisible == NO) {
        if ([[STKPreferences sharedPreferences] iconIsInStack:icon]) {
            isVisible = NO;
        }
    
    }
    return isVisible;
}
%end
/**************************************************************************************************************************/
/**************************************************************************************************************************/


#pragma mark - SBUIController Hook
%hook SBUIController
- (BOOL)clickedMenuButton
{
    if ((STKGetActiveManager()) != nil) {
        STKCloseActiveManager();
        return NO;
    }
    else {
        return %orig();
    }
}

- (BOOL)_activateSwitcher:(NSTimeInterval)animationDuration
{
    STKCloseActiveManager();

    _switcherIsVisible = YES;

    SBIconModel *model = (SBIconModel *)[[%c(SBIconController) sharedInstance] model];
    NSSet *visibleIconTags = MSHookIvar<NSSet *>(model, "_visibleIconTags");
    NSSet *hiddenIconTags = MSHookIvar<NSSet *>(model, "_hiddenIconTags");

    [model setVisibilityOfIconsWithVisibleTags:visibleIconTags hiddenTags:hiddenIconTags];
    
    return %orig(animationDuration);
}

- (void)dismissSwitcherAnimated:(BOOL)animated
{
    _switcherIsVisible = NO;
    %orig();
}

%end

/********************************************************************************************************************************************************************************************************/
/********************************************************************************************************************************************************************************************************/


#pragma mark - Associated Object Keys
static SEL const panGRKey = @selector(acervosPanKey);
static SEL const stackManagerKey = @selector(acervosManagerKey);
static SEL const topGrabberViewKey = @selector(acervosTopGrabberKey);
static SEL const bottomGrabberViewKey = @selector(acervosBottomGrabberKey);
static SEL const recognizerDelegateKey = @selector(acervosDelegateKey);

#pragma mark - Static Function Definitions
static STKStackManager * STKSetupManagerForView(SBIconView *iconView)
{
    __block STKStackManager * stackManager = STKManagerForView(iconView);

    if (!stackManager) {
        NSString *layoutPath = [[STKPreferences sharedPreferences] layoutPathForIcon:iconView.icon];

        // Check if the manager can be created from file
        if ([[NSFileManager defaultManager] fileExistsAtPath:layoutPath]) { 
            stackManager = [[STKStackManager alloc] initWithContentsOfFile:layoutPath];
        }
        else {
            NSArray *stackIcons = [[STKPreferences sharedPreferences] stackIconsForIcon:iconView.icon];
            stackManager = [[STKStackManager alloc] initWithCentralIcon:iconView.icon stackIcons:stackIcons];
            if (![stackManager isEmpty]) {
                [stackManager saveLayoutToFile:layoutPath];
            }
        }

        stackManager.interactionHandler = \
            ^(SBIconView *tappedIconView) {
                if (stackManager != STKGetActiveManager()) {
                    return;
                }

                if (tappedIconView) {
                    stackManager.closesOnHomescreenEdit = NO;
                    [tappedIconView.icon launch];
                    stackManager.closesOnHomescreenEdit = YES;
                    // [stackManager closeStack];
                }
                else if (stackManager.isEmpty) {
                    [stackManager cleanupView];
                }

                STKSetActiveManager(nil);
            };


        objc_setAssociatedObject(iconView, stackManagerKey, stackManager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stackManager release];
    }
    
    // [stackManager recalculateLayouts];
    // [[NSNotificationCenter defaultCenter] postNotificationName:STKRecalculateLayoutsNotification object:nil userInfo:nil];

    if (stackManager.isEmpty == NO) {
        [stackManager setupPreview];
    }
    
    return stackManager;
}

static inline void STKRemoveManagerFromView(SBIconView *iconView)
{
    [STKManagerForView(iconView) cleanupView];
    iconView.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
    objc_setAssociatedObject(iconView, stackManagerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void STKAddPanRecognizerToIconView(SBIconView *iconView)
{
    UIPanGestureRecognizer *panRecognizer = objc_getAssociatedObject(iconView, panGRKey);
    // Don't add a recognizer if it already exists
    if (!panRecognizer) {
        panRecognizer = [[[UIPanGestureRecognizer alloc] initWithTarget:iconView action:@selector(stk_panned:)] autorelease];
        [iconView addGestureRecognizer:panRecognizer];
        objc_setAssociatedObject(iconView, panGRKey, panRecognizer, OBJC_ASSOCIATION_ASSIGN);

        // Setup a delegate, and have the recognizer retain it using associative refs, so that when the recognizer is destroyed, so is the delegate object
        STKRecognizerDelegate *delegate = [[STKRecognizerDelegate alloc] init];
        panRecognizer.delegate = delegate;
        objc_setAssociatedObject(panRecognizer, recognizerDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN);
        [delegate release];
    }
}

static void STKRemovePanRecognizerFromIconView(SBIconView *iconView)
{
    UIPanGestureRecognizer *recognizer = STKPanRecognizerForView(iconView);
    [iconView removeGestureRecognizer:recognizer];

    // Clear out the associative references. 
    objc_setAssociatedObject(recognizer, recognizerDelegateKey, nil, OBJC_ASSOCIATION_RETAIN); // Especially this one. The pan recogniser getting wiped out should remove this already. But still, better to be sure.
    objc_setAssociatedObject(iconView, panGRKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static inline void STKSetupIconView(SBIconView *iconView)
{
    STKAddPanRecognizerToIconView(iconView);
    STKStackManager *manager = STKSetupManagerForView(iconView);

    CGFloat scale = (manager.isEmpty ? 1.f : kCentralIconPreviewScale);
    iconView.iconImageView.transform = CGAffineTransformMakeScale(scale, scale);
}

static inline void STKCleanupIconView(SBIconView *iconView)
{
    STKRemovePanRecognizerFromIconView(iconView);
    STKRemoveManagerFromView(iconView);
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
    return objc_getAssociatedObject(iconView, panGRKey);
}

static inline STKStackManager * STKManagerForView(SBIconView *iconView)
{
    @autoreleasepool {
        return objc_getAssociatedObject(iconView, stackManagerKey);
    }
}

static STKStackManager *_activeManager;
static inline void STKSetActiveManager(STKStackManager *manager)
{
    _activeManager = manager;
}

static inline STKStackManager * STKGetActiveManager(void)
{
    return _activeManager;
}

static inline void STKCloseActiveManager(void)
{
    STKStackManager *manager = STKGetActiveManager();
    [manager closeStackWithCompletionHandler:^{
        if (manager.isEmpty) {
            [manager cleanupView];
        }
    }];

    STKSetActiveManager(nil);
}


#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        CLog(@"Version %s", kPackageVersion);
        CLog(@"Build date: %s, %s", __DATE__, __TIME__);
        
        %init();
    }
}
