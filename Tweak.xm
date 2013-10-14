#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "STKConstants.h"
#import "STKStackManager.h"
#import "STKRecognizerDelegate.h"
#import "STKPreferences.h"
#import "STKIconLayout.h"

#import <SpringBoard/SpringBoard.h>

#import <IconSupport/ISIconSupport.h>
#import <Search/SPSearchResultSection.h>
#import <Search/SPSearchResult.h>

#import <UIKit/UITableViewIndex.h>

#pragma mark - Function Declarations

static STKStackManager * STKSetupManagerForIconView(SBIconView *iconView); // Creates an STKStackManager object, sets it as an associated object on `iconView`, and returns it.
static void STKRemoveManagerFromIconView(SBIconView *iconView); // Removes the manager from view, closing the stack if it was open
static void STKAddPanRecognizerToIconView(SBIconView *iconView);
static void STKRemovePanRecognizerFromIconView(SBIconView *iconView);
static void STKAddGrabberImagesToIconView(SBIconView *iconView);
static void STKRemoveGrabberImagesFromIconView(SBIconView *iconView);

static UIView * STKGetTopGrabber(SBIconView *iconView);
static UIView * STKGetBottomGrabber(SBIconView *iconView);

static void STKPrefsChanged(void);
static void STKUserNotificationCallBack(CFUserNotificationRef userNotification, CFOptionFlags responseFlags);


static inline void STKSetupIconView(SBIconView *iconView); // Adds recogniser and sets up stack manager for the preview
static inline void STKCleanupIconView(SBIconView *iconView); // Removes recogniser and stack manager


// Inline Functions, prevent overhead if called too much.
static inline                   void   STKHandleInteraction(STKStackManager *manager, SBIconView *tappedIconView, BOOL didChangeState, SBIcon *addedIcon);
static inline UIPanGestureRecognizer * STKPanRecognizerForIconView(SBIconView *iconView);
static inline        STKStackManager * STKManagerForView(SBIconView *iconView);
static inline                   void   STKSetActiveManager(STKStackManager *manager);
static inline        STKStackManager * STKGetActiveManager(void);
static inline                   void   STKCloseActiveManager(void);

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
static STKRecognizerDelegate *_recognizerDelegate;
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

- (void)_recycleIconView:(SBIconView *)iconView
{
    STKCleanupIconView(iconView);
    %orig();
}

- (SBIconView *)iconViewForIcon:(SBIcon *)icon
{
    if (STKGetActiveManager() && ICON_IS_IN_STACK(icon)) {
        SBIcon *centralIcon = [[STKPreferences sharedPreferences] centralIconForIcon:icon];
        SBIconView *centralIconView = [self iconViewForIcon:centralIcon];
        STKStackManager *manager = STKManagerForView(centralIconView);
        SBIconView *viewToReturn = nil;
        for (SBIconView *iconView in manager.iconViewsLayout) {
            if (iconView.icon == icon) {
                viewToReturn = iconView;
                break;
            }
        }
        if (viewToReturn) {
            return viewToReturn;
        }
    }

    return %orig();
}

%end


%hook SBIconView
- (void)setIcon:(SBIcon *)icon
{   
    %orig();
    
    if (!icon && STKManagerForView(self)) {
       STKCleanupIconView(self);
    }

    self.location = self.location;
}

- (void)setLocation:(SBIconViewLocation)loc
{
    %orig();
    
    id currentManager = STKManagerForView(self);
    SBIcon *icon = self.icon;

    BOOL isInInfinifolder = ([self.superview isKindOfClass:[UIScrollView class]] && [self.superview.superview isKindOfClass:objc_getClass("SBFolderIconListView")]);

    if (!icon ||
        _wantsSafeIconViewRetrieval || 
        loc != SBIconViewLocationHomeScreen || !self.superview || [self.superview isKindOfClass:%c(SBFolderIconListView)] || isInInfinifolder || 
        [self isInDock] || [[objc_getClass("SBIconController") sharedInstance] grabbedIcon] == self.icon ||
        ![icon isLeafIcon] || [icon isDownloadingIcon] || 
        [[STKPreferences sharedPreferences] iconIsInStack:icon]) {
        // Safe icon retrieval is just a way to be sure setIcon: calls from inside -[SBIconViewMap iconViewForIcon:] aren't intercepted here, causing an infinite loop
        // Don't add recognizer to icons in the stack already
        // In the switcher, -setIcon: is called to change the icon, but doesn't change the icon view, so cleanup.
        STKCleanupIconView(self);
        return;
    }

    if (!currentManager) {
        STKSetupIconView(self);
    }
}


- (BOOL)canReceiveGrabbedIcon:(SBIconView *)iconView
{
    return ((ICON_HAS_STACK(self.icon) || ICON_HAS_STACK(iconView.icon)) ? NO : %orig());
}

#define kBandingFactor  0.1 // The factor by which the distance should be multiplied to simulate the rubber banding effect

static CGPoint                _previousPoint    = CGPointZero;
static CGPoint                _initialPoint     = CGPointZero;
static CGFloat                _previousDistance = 0.0f; // Contains the distance from the initial point.
static STKRecognizerDirection _currentDirection = STKRecognizerDirectionNone; // Stores the direction of the current pan.

static BOOL _cancelledRecognizer = NO;
static BOOL _hasVerticalIcons    = NO;

%new
- (void)stk_panned:(UIPanGestureRecognizer *)sender
{
    UIScrollView *view = (UIScrollView *)[STKListViewForIcon(self.icon) superview];
    STKStackManager *stackManager = STKManagerForView(self);
    STKStackManager *activeManager = STKGetActiveManager();

    if (self.location != SBIconViewLocationHomeScreen) {
        STKCleanupIconView(self);
        return;
    }

    if (stackManager.isExpanded || (activeManager != nil && activeManager != stackManager)) {
        return;
    }

    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint translation = [sender translationInView:view];

        if (!((fabsf(translation.x / translation.y) < 5.0) || translation.x == 0)) {
            // horizontal swipe
            _cancelledRecognizer = YES;
            return;
        }
            
        if ([view isKindOfClass:[UIScrollView class]]) {
            // Turn off scrolling
            view.scrollEnabled = NO;
        }

        // Update the target distance based on icons positions when the pan begins
        // This way, we can be sure that the icons are indeed in the required location 
        STKUpdateTargetDistanceInListView(STKListViewForIcon(self.icon));
        [stackManager setupViewIfNecessary];

        _initialPoint = [sender locationInView:view];
        _currentDirection = STKDirectionFromVelocity([sender velocityInView:view]);
        _previousPoint = _initialPoint; // Previous point is also initial at the start :P

        STKSetActiveManager(stackManager);
        [stackManager touchesBegan];

        _hasVerticalIcons = ([stackManager.appearingIconsLayout iconsForPosition:STKLayoutPositionTop].count > 0) || ([stackManager.appearingIconsLayout iconsForPosition:STKLayoutPositionBottom].count > 0);
    }

    else if (sender.state == UIGestureRecognizerStateChanged) {
        if (view.isDragging || _cancelledRecognizer) {
            _cancelledRecognizer = YES;
            return;
        }

        CGPoint point = [sender locationInView:view];

        // If the swipe is going beyond the point where it started from, stop the swipe.
        if (((_currentDirection == STKRecognizerDirectionUp) && (point.y > _initialPoint.y)) || ((_currentDirection == STKRecognizerDirectionDown) && (point.y < _initialPoint.y))) {
            point = _initialPoint;
        }

        CGFloat change = floorf(fabsf(_previousPoint.y - point.y)); // Vertical
        CGFloat distance = floorf(fabsf(_initialPoint.y - point.y));
        
        if (distance < _previousDistance) {
            // negate the change since swipe is going in the opposite direction
            change = -change;
        }

        CGFloat targetDistance = STKGetCurrentTargetDistance();
        if (!_hasVerticalIcons) {
            targetDistance *= stackManager.distanceRatio;
        }
        if ((change > 0) && (stackManager.currentIconDistance >= targetDistance)) {
            // Factor this down to simulate elasticity when the icons have reached their target locations
            // Stack manager allows the icons to go beyond their targets for a little distance
            change *= kBandingFactor;
        }

        [stackManager touchesDraggedForDistance:change];

        _previousPoint = point;
        _previousDistance = floorf(fabsf(distance));
    }

    else {
        if (_cancelledRecognizer == NO) {
            [stackManager touchesEnded];

            if (stackManager.isExpanded) {
                STKSetActiveManager(stackManager);
            }
            else {
                // The stack has closed, no manager is active no.
                STKSetActiveManager(nil);
            }
        }

        _cancelledRecognizer = NO;

        // Reset the static vars
        _previousPoint = CGPointZero;
        _initialPoint = CGPointZero; 
        _previousDistance = 0.f;
        _currentDirection = STKRecognizerDirectionNone;

        view.scrollEnabled = YES;
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
    if (activeManager && (STKManagerForView(self) == activeManager)) {
        // Only if `self`'s manager is the active manager should we bother forwarding touches.
        UIView *view = [activeManager hitTest:point withEvent:event];
        if (view) {
            return view;
        }    
    }

    IMP hitTestIMP = class_getMethodImplementation([UIView class], _cmd);
    return hitTestIMP(self, _cmd, point, event);
}


- (void)dealloc
{
    if (STKGetActiveManager() == STKManagerForView(self)) {
        STKSetActiveManager(nil);
    }
    %orig();
}

%end


#pragma mark - SBIconController Hook
%hook SBIconController
- (SBFolder *)createNewFolderFromRecipientIcon:(SBIcon *)recepient grabbedIcon:(SBIcon *)grabbed
{ 
    STKCleanupIconView([[%c(SBIconViewMap) homescreenMap] iconViewForIcon:recepient]);
    STKCleanupIconView([[%c(SBIconViewMap) homescreenMap] iconViewForIcon:grabbed]);
    
    return %orig();
}

- (void)animateIcons:(NSArray *)icons intoFolderIcon:(SBFolderIcon *)folderIcon openFolderOnFinish:(BOOL)openFolder complete:(void(^)(void))completionBlock
{
    void (^otherBlock)(void) = ^{
        for (SBIcon *icon in icons) {
            STKCleanupIconView([[%c(SBIconViewMap) homescreenMap] iconViewForIcon:icon]);
        }
        if (completionBlock) {
            completionBlock();
        }
    };

    %orig(icons, folderIcon, openFolder, otherBlock);
}

- (void)setIsEditing:(BOOL)isEditing
{
    BOOL didChange = !(self.isEditing == isEditing);
    %orig(isEditing);
    
    if (didChange) {
        void (^aBlock)(SBIconView *iconView) = ^(SBIconView *iv) {
            if (isEditing) {
                STKRemovePanRecognizerFromIconView(iv);
            }
            else {
                STKStackManager *manager = STKManagerForView(iv);
                if (!manager && iv.icon.isLeafIcon) {
                    iv.location = iv.location;
                    return;
                }

                STKAddPanRecognizerToIconView(iv);
                [manager recalculateLayouts];
            }
        };
        for (SBIconListView *lv in [self valueForKey:@"_rootIconLists"]) {
            [lv makeIconViewsPerformBlock:^(SBIconView *iv) { aBlock(iv); }];
        }

        SBIconListView *folderListView = (SBIconListView *)[[%c(SBIconController) sharedInstance] currentFolderIconList];
        if ([folderListView isKindOfClass:objc_getClass("FEIconListView")]) {
            // FolderEnhancer exists, so process the icons inside folders.
            [folderListView makeIconViewsPerformBlock:^(SBIconView *iv) { aBlock(iv); }];
        }
    }
}

// Ghost all the other stacks' sub-apps when the list view is being ghosted
- (void)setCurrentPageIconsPartialGhostly:(CGFloat)value forRequester:(NSInteger)requester skipIcon:(SBIcon *)icon
{
    %orig(value, requester, icon);

    SBIconListView *listView = [[%c(SBIconController) sharedInstance] currentRootIconList];

    [listView makeIconViewsPerformBlock:^(SBIconView *iconView) {
        if (iconView.icon == icon || iconView.icon == [STKGetActiveManager() centralIcon]) {
            return;
        }

        STKStackManager *iconViewManager = STKManagerForView(iconView);
        [iconViewManager setStackIconAlpha:value];
    }];
}

- (void)setCurrentPageIconsGhostly:(BOOL)shouldGhost forRequester:(NSInteger)requester skipIcon:(SBIcon *)icon
{
    %orig(shouldGhost, requester, icon);

    SBIconListView *listView = [[%c(SBIconController) sharedInstance] currentRootIconList];
    NSNumber *ghostedRequesters = [self valueForKey:@"_ghostedRequesters"];

    [listView makeIconViewsPerformBlock:^(SBIconView *iconView) {
        if (iconView.icon == icon || iconView.icon == [STKGetActiveManager() centralIcon]) {
            return;
        }
        
        STKStackManager *iconViewManager = STKManagerForView(iconView);
        if ([ghostedRequesters integerValue] > 0 || shouldGhost) {
            // ignore  `shouldGhost` if ghostedRequesters > 0
            [iconViewManager setStackIconAlpha:0.0];
        }
        else if (!shouldGhost) {
            [iconViewManager setStackIconAlpha:1.f];
        }
    }];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    STKCloseActiveManager();
    %orig(scrollView);
}
%end



#pragma mark - SBIconModel Hook
%hook SBIconModel
- (BOOL)isIconVisible:(SBIcon *)icon
{
    BOOL isVisible = %orig();

    // Picked this one up from https://github.com/big-boss/Libhide/blob/master/dylib/classes/iconhide.xm#L220
    BOOL isInSpotlight = [((SBIconController *)[%c(SBIconController) sharedInstance]).searchController.searchView isKeyboardVisible];

    if (!(_switcherIsVisible || [(SpringBoard *)[UIApplication sharedApplication] _isSwitcherShowing] || [[%c(SBUIController) sharedInstance] isSwitcherShowing])
        && isInSpotlight == NO) {
        if ([[STKPreferences sharedPreferences] iconIsInStack:icon]) {
            isVisible = NO;
        }
    
    }
    return isVisible;
}
%end


#pragma mark - SBUIController Hook
%hook SBUIController
- (BOOL)clickedMenuButton
{
    STKStackManager *activeManager = STKGetActiveManager();
    if (activeManager && ![(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication]) {
        BOOL manDidIntercept = [activeManager handleHomeButtonPress];
        if (!manDidIntercept) {
            STKCloseActiveManager();
        }
        return YES;
    }
    else {
        return %orig();
    }
}

- (BOOL)_activateSwitcher:(NSTimeInterval)animationDuration
{
    if (STKGetActiveManager().isSelecting == NO) {
        STKCloseActiveManager();
    }

    _switcherIsVisible = YES;

    SBIconModel *model = (SBIconModel *)[[%c(SBIconController) sharedInstance] model];
    NSSet *&visibleIconTags = MSHookIvar<NSSet *>(model, "_visibleIconTags");
    NSSet *&hiddenIconTags = MSHookIvar<NSSet *>(model, "_hiddenIconTags");

    [model setVisibilityOfIconsWithVisibleTags:visibleIconTags hiddenTags:hiddenIconTags];
    
    return %orig(animationDuration);
}

- (void)dismissSwitcherWithoutUnhostingApp
{
    _switcherIsVisible = NO;
    %orig();
}

- (void)dismissSwitcherAnimated:(BOOL)animated
{
    _switcherIsVisible = NO;
    %orig();
}

%end

%hook SBAppSwitcherController
- (void)viewWillDisappear
{
    _switcherIsVisible = NO;
    %orig();
}
%end

#pragma mark - Search Agent Hook
%hook SPSearchAgent
- (id)sectionAtIndex:(NSUInteger)idx
{
    SPSearchResultSection *ret = %orig();
    if (ret.hasDomain && ret.domain == 4) {
        NSString *appID = ret.displayIdentifier;
        SBIcon *icon = [[(SBIconController *)[%c(SBIconController) sharedInstance] model] expectedIconForDisplayIdentifier:appID];
        if (ICON_IS_IN_STACK(icon)) {
            SBIcon *centralIcon = [[STKPreferences sharedPreferences] centralIconForIcon:icon];
            [(SPSearchResult *)ret.results[0] setAuxiliaryTitle:centralIcon.displayName];
            [(SPSearchResult *)ret.results[0] setAuxiliarySubtitle:centralIcon.displayName];
        }
    }
    return ret;
}
%end
/********************************************************************************************************************************************/
/********************************************************************************************************************************************/


/********************************************************************************************************************************************/
/********************************************************************************************************************************************/
#pragma mark - SpringBoard Hook
%hook SpringBoard
- (void)_reportAppLaunchFinished
{
    %orig;

    if (![STKPreferences sharedPreferences].welcomeAlertShown) {
        NSDictionary *fields = @{(id)kCFUserNotificationAlertHeaderKey          : @"Apex",
                                 (id)kCFUserNotificationAlertMessageKey         : @"Thanks for purchasing!\nSwipe down on any app icon and tap the \"+\" to get started.",
                                 (id)kCFUserNotificationDefaultButtonTitleKey   : @"OK",
                                 (id)kCFUserNotificationAlternateButtonTitleKey : @"Settings"};

        SInt32 error;
        CFUserNotificationRef notificationRef = CFUserNotificationCreate(kCFAllocatorDefault, 0, kCFUserNotificationNoteAlertLevel, &error, (CFDictionaryRef)fields);
        // Get and add a run loop source to the current run loop to get notified when the alert is dismissed
        CFRunLoopSourceRef runLoopSource = CFUserNotificationCreateRunLoopSource(kCFAllocatorDefault, notificationRef, STKUserNotificationCallBack, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        if (error == 0) {
            [STKPreferences sharedPreferences].welcomeAlertShown = YES;
        }
    }
}
%end

#pragma mark - User Notification Callback
static void STKUserNotificationCallBack(CFUserNotificationRef userNotification, CFOptionFlags responseFlags)
{
    if ((responseFlags & 0x3) == kCFUserNotificationAlternateResponse) {
        // Open settings to custom bundle
        [(SpringBoard *)[UIApplication sharedApplication] applicationOpenURL:[NSURL URLWithString:@"prefs:root=Apex"] publicURLsOnly:NO];
    }
    CFRelease(userNotification);
}


#pragma mark - Compatibility Hooks
#pragma mark - Folder Enhancer Compatibility
%group FECompat
%hook FEGridFolderView
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    STKCloseActiveManager();
    %orig();
}
%end
%end

#pragma mark - Zephyr
%group ZephyrCompat
%hook ZephyrSwitcherGesture

- (void)handleGestureBegan:(id)gesture withLocation:(float)location
{
    _switcherIsVisible = YES;

    SBIconModel *model = (SBIconModel *)[[%c(SBIconController) sharedInstance] model];
    NSSet *&visibleIconTags = MSHookIvar<NSSet *>(model, "_visibleIconTags");
    NSSet *&hiddenIconTags = MSHookIvar<NSSet *>(model, "_hiddenIconTags");

    [model setVisibilityOfIconsWithVisibleTags:visibleIconTags hiddenTags:hiddenIconTags];

    %orig(gesture, location);
}

- (void)resetAfterCancelDismissGesture
{
    _switcherIsVisible = NO;
    %orig();
}

- (void)handleGestureEnded:(id)gesture withLocation:(CGFloat)location velocity:(CGPoint)velocity completionType:(int)type
{
    _switcherIsVisible = NO;
    %orig();
}

%end
%end

#pragma mark - Associated Object Keys
// Assigned to SELs for easy access from cycript.
static SEL const panGRKey              = @selector(apexPanKey);
static SEL const stackManagerKey       = @selector(apexManagerKey);
static SEL const topGrabberViewKey     = @selector(apexTopGrabberKey);
static SEL const bottomGrabberViewKey  = @selector(apexBottomGrabberKey);
static SEL const prefsCallbackObserver = @selector(apexCallbackKey);
#pragma mark - Static Function Definitions
static STKStackManager * STKSetupManagerForIconView(SBIconView *iconView)
{
    STKStackManager *stackManager = STKManagerForView(iconView);
    NSString *layoutPath = [[STKPreferences sharedPreferences] layoutPathForIcon:iconView.icon];

    if (!stackManager) {
        if (ICON_HAS_STACK(iconView.icon)) {
            NSDictionary *cachedLayout = [[STKPreferences sharedPreferences] cachedLayoutDictForIcon:iconView.icon];
            if (cachedLayout) {
                stackManager = [[STKStackManager alloc] initWithCentralIcon:iconView.icon withCustomLayout:cachedLayout];
                if (stackManager.layoutDiffersFromFile) {
                    [stackManager saveLayoutToFile:layoutPath];
                }
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

        stackManager.showsPreview = [STKPreferences sharedPreferences].previewEnabled;

        stackManager.interactionHandler = ^(STKStackManager *manager, SBIconView *tappedIconView, BOOL didChangeState, SBIcon *addedIcon) {
            STKHandleInteraction(manager, tappedIconView, didChangeState, addedIcon);
        };

        objc_setAssociatedObject(iconView, stackManagerKey, stackManager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stackManager release];
    }

    if (stackManager.isEmpty == NO && stackManager.showsPreview) {
        [stackManager setupPreview];
    }
    
    return stackManager;
}

static inline void STKHandleInteraction(STKStackManager *manager, SBIconView *tappedIconView, BOOL didChangeState, SBIcon *addedIcon)
{
    if (didChangeState) {
        if (manager.isEmpty) {
            [[STKPreferences sharedPreferences] removeLayoutForIcon:manager.centralIcon];
            if (!manager.showsPreview) {
                STKRemoveGrabberImagesFromIconView([[%c(SBIconViewMap) homescreenMap] iconViewForIcon:manager.centralIcon]);
            }
        }
        else {
            SBIcon *centralIconForManagerWithAddedIcon = [[STKPreferences sharedPreferences] centralIconForIcon:addedIcon];
            if (centralIconForManagerWithAddedIcon) {
                SBIconView *otherView = [[%c(SBIconViewMap) homescreenMap] iconViewForIcon:centralIconForManagerWithAddedIcon];
                STKStackManager *otherManager = STKManagerForView(otherView);
                if (otherManager != manager || !otherManager) {
                    [[STKPreferences sharedPreferences] removeCachedLayoutForIcon:centralIconForManagerWithAddedIcon];

                    if (otherManager) {
                        [otherManager removeIconFromAppearingIcons:addedIcon];

                        if (otherManager.isEmpty) {
                            [[STKPreferences sharedPreferences] removeLayoutForIcon:otherManager.centralIcon];
                            [otherManager cleanupView];
                            [[%c(SBIconViewMap) homescreenMap] iconViewForIcon:otherManager.centralIcon].transform = CGAffineTransformMakeScale(1.f, 1.f);
                        }
                        else {
                            [otherManager saveLayoutToFile:[[STKPreferences sharedPreferences] layoutPathForIcon:otherManager.centralIcon]];
                        }
                    }
                    else {
                        NSDictionary *cachedLayout = [[STKPreferences sharedPreferences] cachedLayoutDictForIcon:centralIconForManagerWithAddedIcon];

                        STKIconLayout *layout = [STKIconLayout layoutWithDictionary:cachedLayout];
                        [layout removeIcon:addedIcon];

                        if ([layout allIcons].count > 0) {
                            [STKStackManager saveLayout:layout 
                                                 toFile:[[STKPreferences sharedPreferences] layoutPathForIcon:centralIconForManagerWithAddedIcon]
                                                forIcon:centralIconForManagerWithAddedIcon];
                        }
                        else {
                            [[STKPreferences sharedPreferences] removeLayoutForIcon:centralIconForManagerWithAddedIcon];
                        }
                        STKSetupIconView(otherView);
                    }

                }
            }
            if (!manager.showsPreview) {
                STKAddGrabberImagesToIconView([[%c(SBIconViewMap) homescreenMap] iconViewForIcon:manager.centralIcon]);
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
        [tappedIconView.icon launch];
        if ([[STKPreferences sharedPreferences] shouldCloseOnLaunch]) {
            STKCloseActiveManager();
        }
    }
    else {
        STKSetActiveManager(nil);
    }
}

static void STKRemoveManagerFromIconView(SBIconView *iconView)
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

        if (!_recognizerDelegate) {
            // Use the same delegate everywhere
            _recognizerDelegate = [[STKRecognizerDelegate alloc] init];
        }
        panRecognizer.delegate = _recognizerDelegate;
    }
}

static void STKRemovePanRecognizerFromIconView(SBIconView *iconView)
{
    UIPanGestureRecognizer *recognizer = STKPanRecognizerForIconView(iconView);
    [iconView removeGestureRecognizer:recognizer];

    objc_setAssociatedObject(iconView, panGRKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void STKAddGrabberImagesToIconView(SBIconView *iconView)
{
    UIImageView *topView = objc_getAssociatedObject(iconView, topGrabberViewKey);
    if (!topView) {
        topView = [[[UIImageView alloc] initWithImage:UIIMAGE_NAMED(@"TopGrabber")] autorelease];
        topView.center = (CGPoint){iconView.iconImageView.center.x, (iconView.iconImageView.frame.origin.y)};
        [iconView insertSubview:topView belowSubview:iconView.iconImageView];

        objc_setAssociatedObject(iconView, topGrabberViewKey, topView, OBJC_ASSOCIATION_ASSIGN);
    }

    UIImageView *bottomView = objc_getAssociatedObject(iconView, bottomGrabberViewKey);
    if (!bottomView) {
        bottomView = [[[UIImageView alloc] initWithImage:UIIMAGE_NAMED(@"BottomGrabber")] autorelease];
        bottomView.center = (CGPoint){iconView.iconImageView.center.x, (CGRectGetMaxY(iconView.iconImageView.frame) - 1)};
        [iconView insertSubview:bottomView belowSubview:iconView.iconImageView];
        objc_setAssociatedObject(iconView, bottomGrabberViewKey, bottomView, OBJC_ASSOCIATION_ASSIGN);
    }
}

static void STKRemoveGrabberImagesFromIconView(SBIconView *iconView)
{
    [(UIView *)objc_getAssociatedObject(iconView, topGrabberViewKey) removeFromSuperview];
    [(UIView *)objc_getAssociatedObject(iconView, bottomGrabberViewKey) removeFromSuperview];  

    objc_setAssociatedObject(iconView, topGrabberViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(iconView, bottomGrabberViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
}


static UIView * STKGetTopGrabber(SBIconView *iconView)
{
    return objc_getAssociatedObject(iconView, topGrabberViewKey);
}

static UIView * STKGetBottomGrabber(SBIconView *iconView)
{
    return objc_getAssociatedObject(iconView, bottomGrabberViewKey);
}


static void STKPrefsChanged(void)
{
    BOOL previewEnabled = [STKPreferences sharedPreferences].previewEnabled;

    void (^aBlock)(SBIconView *iconView) = ^(SBIconView *iconView) {
        if (!iconView) {
            return;
        }
        
        STKStackManager *manager = STKManagerForView(iconView);
        if (!manager) {
            return;
        }

        if (!manager.isEmpty) {
            if (previewEnabled) {
                iconView.iconImageView.transform = CGAffineTransformMakeScale(kCentralIconPreviewScale, kCentralIconPreviewScale);
                STKRemoveGrabberImagesFromIconView(iconView);
                manager.topGrabberView = nil;
                manager.bottomGrabberView = nil;
            }
            else {
                iconView.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
                STKAddGrabberImagesToIconView(iconView);
                manager.topGrabberView = STKGetTopGrabber(iconView);
                manager.bottomGrabberView = STKGetBottomGrabber(iconView);
            }
        }

        manager.showsPreview = previewEnabled;
    };

    for (SBIconListView *listView in [[%c(SBIconController) sharedInstance] valueForKey:@"_rootIconLists"]){
        [listView makeIconViewsPerformBlock:^(SBIconView *iconView) { aBlock(iconView); }];
    }

    SBIconListView *folderListView = (SBIconListView *)[[%c(SBIconController) sharedInstance] currentFolderIconList];
    if ([folderListView isKindOfClass:objc_getClass("FEIconListView")]) {
        [folderListView makeIconViewsPerformBlock:^(SBIconView *iv) { aBlock(iv); }];
    }
}



#pragma mark - Inliner Definitions
static inline void STKSetupIconView(SBIconView *iconView)
{
    if (iconView.icon == STKGetActiveManager().centralIcon) {
        return;
    }
    
    if (![(SBIconController *)[%c(SBIconController) sharedInstance] isEditing]) {
        // Don't add a recognizer if icons are being edited
        STKAddPanRecognizerToIconView(iconView);
    }
    STKStackManager *manager = STKSetupManagerForIconView(iconView);

    CGFloat scale = (manager.isEmpty || !manager.showsPreview ? 1.f : kCentralIconPreviewScale);
    iconView.iconImageView.transform = CGAffineTransformMakeScale(scale, scale);

    if (manager && !manager.showsPreview && !manager.isEmpty) {
        STKAddGrabberImagesToIconView(iconView);
        manager.topGrabberView = STKGetTopGrabber(iconView);
        manager.bottomGrabberView = STKGetBottomGrabber(iconView);
    }
}

static inline void STKCleanupIconView(SBIconView *iconView)
{       
    STKRemovePanRecognizerFromIconView(iconView);
    STKRemoveManagerFromIconView(iconView);
    STKRemoveGrabberImagesFromIconView(iconView);
}

static inline STKRecognizerDirection STKDirectionFromVelocity(CGPoint point)
{
    if (point.y == 0) {
        return STKRecognizerDirectionNone;
    }

    return ((point.y < 0) ? STKRecognizerDirectionUp : STKRecognizerDirectionDown);
}

static inline UIPanGestureRecognizer * STKPanRecognizerForIconView(SBIconView *iconView)
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
    [_activeManager release];
    _activeManager = [manager retain];
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
        STKLog(@"Initializing");
        %init();
        
        dlopen("/Library/MobileSubstrate/DynamicLibraries/IconSupport.dylib", RTLD_NOW);
    
        [[objc_getClass("ISIconSupport") sharedInstance] addExtension:kSTKTweakName];

        void *feHandle = dlopen("/Library/MobileSubstrate/DynamicLibraries/FolderEnhancer.dylib", RTLD_NOW);
        if (feHandle) {
            %init(FECompat);
        }

        void *zephyrHandle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Zephyr.dylib", RTLD_NOW);
        if (zephyrHandle) {
            %init(ZephyrCompat);
        }

        // Set up the singleton
        [STKPreferences sharedPreferences];
        [[STKPreferences sharedPreferences] registerCallbackForPrefsChange:^{
            STKPrefsChanged();
        }];
    }
}
