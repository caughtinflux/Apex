#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "STKConstants.h"
#import "STKStackManager.h"
#import "STKRecognizerDelegate.h"
#import "STKPreferences.h"
#import "STKIconLayout.h"
#import "SBIconModel+Additions.h"

#import <SpringBoard/SpringBoard.h>
#import <objc/message.h>
#import <notify.h>
#import <stdlib.h>

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


/****************************************************************************************************************************************
                                                      STATIC VARIABLES
****************************************************************************************************************************************/
static BOOL _wantsSafeIconViewRetrieval;
static BOOL _switcherIsVisible;
/****************************************************************************************************************************************/
/****************************************************************************************************************************************/




/****************************************************************************************************************************************/
/****************************************************  REAL SHIT STARTS  ****************************************************************/
/****************************************************************************************************************************************/

%hook SBIconViewMap
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

- (void)setLocation:(SBIconViewLocation)loc
{   
    %orig();
    
    if ([[%c(SBIconController) sharedInstance] isEditing]) {
        return;
    }
    
    SBIcon *icon = self.icon;
    if (!icon ||
        _wantsSafeIconViewRetrieval || 
        loc != SBIconViewLocationHomeScreen || [self.superview isKindOfClass:%c(SBFolderIconListView)] || [self isInDock] ||
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
}

- (BOOL)canReceiveGrabbedIcon:(SBIconView *)iconView
{
    return ((ICON_HAS_STACK(self.icon) || ICON_HAS_STACK(iconView.icon)) ? NO : %orig());
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

    if (self.location != SBIconViewLocationHomeScreen) {
        STKCleanupIconView(self);
        return;
    }

    if (stackManager.isExpanded || (activeManager != nil && activeManager != stackManager) || ([self.superview isKindOfClass:%c(SBFolderIconListView)])) {
        return;
    }

    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint translation = [sender translationInView:view];

        if (!((fabsf(translation.x / translation.y) < 5.0) || translation.x == 0)) {
            // horizontal swipe
            sender.enabled = NO;
            sender.enabled = YES;
            return;
        }
            
        // Turn off scrolling in the list view
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
    BOOL didChange = !(self.isEditing == isEditing);
    %orig(isEditing);
    
    if (didChange) {
        for (SBIconListView *lv in [self valueForKey:@"_rootIconLists"]) {
            [lv makeIconViewsPerformBlock:^(SBIconView *iv) {
                if (isEditing) {
                    STKRemovePanRecognizerFromIconView(iv);
                }
                else {
                    STKAddPanRecognizerToIconView(iv);
                    STKStackManager *manager = STKManagerForView(iv);
                    [manager recalculateLayouts];
                }
            }];
        }
    }
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
/****************************************************************************************************************************************/
/****************************************************************************************************************************************/


/**************************************************************************************************************************/
/****************************************************** Icon Hiding *******************************************************/
#pragma mark - SBIconModel Hook
%hook SBIconModel
- (BOOL)isIconVisible:(SBIcon *)icon
{
    BOOL isVisible = %orig();

    // Picked this one up from https://github.com/big-boss/Libhide/blob/master/dylib/classes/iconhide.xm#L220
    BOOL isInSpotlight = [((SBIconController *)[%c(SBIconController) sharedInstance]).searchController.searchView isKeyboardVisible];

    if (_switcherIsVisible == NO && isInSpotlight == NO) {
        if ([[STKPreferences sharedPreferences] iconIsInStack:icon]) {
            isVisible = NO;
        }
    
    }
    return isVisible;
}

%new
- (void)stk_reloadIconVisibility
{
    [self stk_reloadIconVisibilityForSwitcher:NO];
}

%new
- (void)stk_reloadIconVisibilityForSwitcher:(BOOL)forSwitcher
{    
    NSSet *visibleIconTags = MSHookIvar<NSSet *>(self, "_visibleIconTags");
    NSSet *hiddenIconTags = MSHookIvar<NSSet *>(self, "_hiddenIconTags");

    [self setVisibilityOfIconsWithVisibleTags:visibleIconTags hiddenTags:hiddenIconTags];
    if (!forSwitcher) {
        [self layout];
    }
}

%end
/**************************************************************************************************************************/
/**************************************************************************************************************************/


#pragma mark - SBUIController Hook
%hook SBUIController
- (BOOL)clickedMenuButton
{
    STKStackManager *activeManager = STKGetActiveManager();
    if (activeManager) {
        BOOL manDidIntercept = [activeManager handleHomeButtonPress];
        if (!manDidIntercept) {
            [activeManager closeStack];
        }
        return YES;
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
    [model stk_reloadIconVisibilityForSwitcher:YES];
    
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

        if (ICON_HAS_STACK(iconView.icon)) {
            NSString *layoutPath = [[STKPreferences sharedPreferences] layoutPathForIcon:iconView.icon];
            if (![STKStackManager isValidLayoutAtPath:layoutPath]) {
                [[STKPreferences sharedPreferences] removeLayoutForIcon:iconView.icon];
            }
            else {
                stackManager = [[STKStackManager alloc] initWithContentsOfFile:layoutPath];
                if (stackManager.layoutDiffersFromFile) {
                    [stackManager saveLayoutToFile:layoutPath];
                }
                else if (!stackManager) {
                    // Control should not get here, since
                    // we are already checking if the layout is invalid
                    NSArray *stackIcons = [[STKPreferences sharedPreferences] stackIconsForIcon:iconView.icon];
                    stackManager = [[STKStackManager alloc] initWithCentralIcon:iconView.icon stackIcons:stackIcons];
                    if (![stackManager isEmpty]) {
                        [stackManager saveLayoutToFile:layoutPath];
                    }
                }    
            }
        }
        else {            
            stackManager = [[STKStackManager alloc] initWithCentralIcon:iconView.icon stackIcons:nil];
        }

        stackManager.interactionHandler = \
            ^(STKStackManager *manager, SBIconView *tappedIconView, BOOL didChangeState, SBIcon *addedIcon) {
                if (didChangeState) {
                    if (manager.isEmpty) {
                        [[STKPreferences sharedPreferences] removeLayoutForIcon:stackManager.centralIcon];
                    }
                    else {
                        SBIcon *centralIconForManagerWithAddedIcon = [[STKPreferences sharedPreferences] centralIconForIcon:addedIcon];
                        if (centralIconForManagerWithAddedIcon) {
                            STKStackManager *otherManager = STKManagerForView([[%c(SBIconViewMap) homescreenMap] iconViewForIcon:centralIconForManagerWithAddedIcon]);
                            [otherManager removeIconFromAppearingIcons:addedIcon];
                            if (otherManager.isEmpty) {
                                [[STKPreferences sharedPreferences] removeLayoutForIcon:otherManager.centralIcon];
                            }
                            else {
                                [otherManager saveLayoutToFile:[[STKPreferences sharedPreferences] layoutPathForIcon:otherManager.centralIcon]];
                            }
                        }

                        NSString *layoutPath = [[STKPreferences sharedPreferences] layoutPathForIcon:manager.centralIcon];
                        [manager saveLayoutToFile:layoutPath];
                    }
                    [[STKPreferences sharedPreferences] reloadPreferences];
                    return; 
                }

                if (manager != STKGetActiveManager()) {
                    return;
                }

                if (tappedIconView) {
                    manager.closesOnHomescreenEdit = NO;
                    [tappedIconView.icon launch];
                    manager.closesOnHomescreenEdit = YES;
                    [manager closeStack];
                }
                
                STKSetActiveManager(nil);
            };


        objc_setAssociatedObject(iconView, stackManagerKey, stackManager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stackManager release];
    }

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
    if (!iconView) {
        return;
    }
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

    for (UIGestureRecognizer *r in iconView.gestureRecognizers) {
        if ([r isKindOfClass:[UIPanGestureRecognizer class]]) {
            [iconView removeGestureRecognizer:r];
        }
    }
}

static inline void STKSetupIconView(SBIconView *iconView)
{
    if (iconView.icon == STKGetActiveManager().centralIcon) {
        return;
    }
    
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
    [STKGetActiveManager() closeStack];
    STKSetActiveManager(nil);
}


#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        CLog(@"Version %s", kPackageVersion);
        CLog(@"Build date: %s, %s", __DATE__, __TIME__);
        
        %init();

        // Set up the singleton
        [STKPreferences sharedPreferences];
    }
}
