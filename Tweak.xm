#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <SpringBoard/SpringBoard.h>
#import <Search/SPSearchResultSection.h>
#import <Search/SPSearchResult.h>

#import <IconSupport/ISIconSupport.h>

#import "STKConstants.h"
#import "STKStack.h"
#import "STKStackController.h"
#import "STKPreferences.h"
#import "STKIconLayout.h"
#import "MobileGestalt.h"

#pragma mark - Function Declarations
static void STKWelcomeAlertCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags);

static BOOL _switcherIsVisible;
static BOOL _wantsSafeIconViewRetrieval;

#pragma mark - SBIconViewMap Hook
%hook SBIconViewMap
%new
- (SBIconView *)safeIconViewForIcon:(SBIcon *)icon
{
    _wantsSafeIconViewRetrieval = YES;
    SBIconView *iconView = [self iconViewForIcon:icon];
    _wantsSafeIconViewRetrieval = NO;
    return iconView;
}

- (void)_addIconView:(SBIconView *)iconView forIcon:(SBIcon *)icon
{
    %orig(iconView, icon);
    if (iconView.icon != icon) {
        iconView.icon = icon;
    }
    [[STKStackController sharedInstance] createOrRemoveStackForIconView:iconView];
}

- (void)_recycleIconView:(SBIconView *)iconView
{
    [[STKStackController sharedInstance] removeStackFromIconView:iconView];
    %orig();
}

- (SBIconView *)iconViewForIcon:(SBIcon *)icon
{
    if ([STKStackController sharedInstance].activeStack && ICON_IS_IN_STACK(icon)) {
        SBIcon *centralIcon = [[STKPreferences sharedPreferences] centralIconForIcon:icon];
        SBIconView *centralIconView = [self iconViewForIcon:centralIcon];
        STKStack *stack = [[STKStackController sharedInstance] stackForIconView:centralIconView];
        SBIconView *viewToReturn = nil;
        for (SBIconView *iconView in stack.iconViewLayout) {
            if (iconView.icon == icon) {
                viewToReturn = iconView;
                break;
            }
        }
        if (viewToReturn) {
            return viewToReturn;
        }
    }
    _wantsSafeIconViewRetrieval = YES;
    id ret = %orig(icon);
    _wantsSafeIconViewRetrieval = NO;

    return ret;
}

%end

%hook SBIcon
- (NSString *)badgeTextForLocation:(SBIconViewLocation)location
{
    if ([[STKStackController sharedInstance] activeStack].centralIcon == self) {
        return %orig();
    }

    NSNumber *badgeNumber = [self badgeNumberOrString];
    NSString *badgeText = nil;
    if ([badgeNumber isKindOfClass:[NSNumber class]]) {
        if ([badgeNumber integerValue] == 0) {
            badgeNumber = nil;
        }
        else {
            badgeText = [badgeNumber stringValue];
        }
    }
    else {
        badgeText = %orig();
    }
    return badgeText;
}

- (id)badgeNumberOrString
{
    NSNumber *ret = %orig() ?: @(0);
    if ([ret isKindOfClass:[NSNumber class]] && ICON_HAS_STACK(self)) {
        NSInteger subAppTotal = 0;
        for (SBIcon *icon in [[STKPreferences sharedPreferences] stackIconsForIcon:self]) {
            subAppTotal += [icon badgeValue];
        }
        ret = @([ret integerValue] + subAppTotal);
    }
    return ret;
}

- (void)noteBadgeDidChange
{
    %orig();
    if (ICON_IS_IN_STACK(self)) {
        [[[STKPreferences sharedPreferences] centralIconForIcon:self] noteBadgeDidChange];
    }
}

%end 

#pragma mark - SBIconView Hook
%hook SBIconView
- (void)setIcon:(SBIcon *)icon
{   
    %orig();
    if (!icon && [[STKStackController sharedInstance] stackForIconView:self]) {
       [[STKStackController sharedInstance] removeStackFromIconView:self];
    }
    self.location = self.location;
}

- (void)setLocation:(SBIconViewLocation)loc
{
    %orig();
    if (!_wantsSafeIconViewRetrieval) {
        [[STKStackController sharedInstance] createOrRemoveStackForIconView:self];
    }
}

- (BOOL)canReceiveGrabbedIcon:(SBIconView *)iconView
{
    return ((ICON_HAS_STACK(self.icon) || ICON_HAS_STACK(iconView.icon)) ? NO : %orig());
}

- (void)dealloc
{
    if ([STKStackController sharedInstance].activeStack == [[STKStackController sharedInstance] stackForIconView:self]) {
        [STKStackController sharedInstance].activeStack = nil;
    }
    %orig();
}
%end

%hook SBIconImageView
- (void)setTransform:(CGAffineTransform)transform
{
    %orig(transform);
    SBIconView *iconView = (SBIconView *)self.superview.superview;
    if (iconView && [iconView isKindOfClass:objc_getClass("SBIconView")]) {
        UIImageView *shadowView = [iconView valueForKey:@"_shadow"];
        shadowView.transform = transform;
    }
}
%end

#pragma mark - SBIconListView Hook
%hook SBIconListView
%new
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    STKStack *activeStack = [STKStackController sharedInstance].activeStack;
    if (activeStack) {
        SBIconView *centralIconView = [[%c(SBIconViewMap) homescreenMap] mappedIconViewForIcon:activeStack.centralIcon];
        point = [centralIconView convertPoint:point fromView:self];
        UIView *view = [activeStack hitTest:point withEvent:event];
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
- (SBFolder *)createNewFolderFromRecipientIcon:(SBIcon *)recipient grabbedIcon:(SBIcon *)grabbed
{ 
    [[STKStackController sharedInstance] removeStackFromIconView:[[%c(SBIconViewMap) homescreenMap] iconViewForIcon:recipient]];
    [[STKStackController sharedInstance] removeStackFromIconView:[[%c(SBIconViewMap) homescreenMap] iconViewForIcon:grabbed]];
    return %orig();
}

- (void)animateIcons:(NSArray *)icons intoFolderIcon:(SBFolderIcon *)folderIcon openFolderOnFinish:(BOOL)openFolder complete:(void(^)(void))completionBlock
{
    void (^otherBlock)(void) = ^{
        for (SBIcon *icon in icons) {
            [[STKStackController sharedInstance] removeStackFromIconView:[[%c(SBIconViewMap) homescreenMap] iconViewForIcon:icon]];
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
    if (!didChange || isEditing) {
        return;
    }
    void (^editHandler)(SBIconView *iconView) = ^(SBIconView *iv) {
        STKStack *stack = [[STKStackController sharedInstance] stackForIconView:iv];
        if (!stack && iv.icon.isLeafIcon) {
            iv.location = iv.location;
            return;
        }
        [stack recalculateLayouts];
    }; 
    for (SBIconListView *lv in [self valueForKey:@"_rootIconLists"]) {
        [lv makeIconViewsPerformBlock:editHandler];
    }
    SBIconListView *folderListView = (SBIconListView *)[[%c(SBIconController) sharedInstance] currentFolderIconList];
    if ([folderListView isKindOfClass:objc_getClass("FEIconListView")]) {
        // FolderEnhancer exists, so process the icons inside folders.
        [folderListView makeIconViewsPerformBlock:editHandler];
    }
    [[self dock] makeIconViewsPerformBlock:editHandler];
}

// Ghost all the other stacks' sub-apps when the list view is being ghosted
- (void)setCurrentPageIconsPartialGhostly:(CGFloat)value forRequester:(NSInteger)requester skipIcon:(SBIcon *)icon
{
    %orig(value, requester, icon);

    void (^processor)(SBIconView *) = ^(SBIconView *iconView) {
        if (iconView.icon == icon || iconView.icon == [[STKStackController sharedInstance].activeStack centralIcon]) {
            return;
        }
        STKStack *stack = [[STKStackController sharedInstance] stackForIconView:iconView];
        [stack setIconAlpha:value];
    };
    [[self currentRootIconList] makeIconViewsPerformBlock:processor];
    [[self dock] makeIconViewsPerformBlock:processor];
}

- (void)setCurrentPageIconsGhostly:(BOOL)shouldGhost forRequester:(NSInteger)requester skipIcon:(SBIcon *)icon
{
    %orig(shouldGhost, requester, icon);
 
    NSNumber *ghostedRequesters = [self valueForKey:@"_ghostedRequesters"];
    void (^processor)(SBIconView *) = ^(SBIconView *iconView) {
        if (iconView.icon == icon || iconView.icon == [[STKStackController sharedInstance].activeStack centralIcon]) {
            return;
        }
        STKStack *iconViewStack = [[STKStackController sharedInstance] stackForIconView:iconView];
        if ([ghostedRequesters integerValue] > 0 || shouldGhost) {
            // ignore  `shouldGhost` if ghostedRequesters > 0
            [iconViewStack setIconAlpha:0.0];
        }
        else if (!shouldGhost) {
            [iconViewStack setIconAlpha:1.f];
        }
    };
    [[self currentRootIconList] makeIconViewsPerformBlock:processor];
    [[self dock] makeIconViewsPerformBlock:processor];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [[STKStackController sharedInstance] closeActiveStack];
    %orig(scrollView);
}

- (BOOL)relayout
{
    BOOL k = %orig();
    // When this method is called, the root icon lists are re-created, but the dock isn't(?), so the dock ends up with a weird stack.
    // So, let's do it manually
    [[self dock] makeIconViewsPerformBlock:^(SBIconView *iconView) {
        [[[STKStackController sharedInstance] stackForIconView:iconView] recalculateLayouts];
    }];
    return k;
}

%end


#pragma mark - SBIconModel Hook
%hook SBIconModel
- (BOOL)isIconVisible:(SBIcon *)icon
{
    BOOL isVisible = %orig();

    // Picked this one up from https://github.com/big-boss/Libhide/blob/master/dylib/classes/iconhide.xm#L220
    BOOL isInSpotlight = [((SBIconController *)[%c(SBIconController) sharedInstance]).searchController.searchView isKeyboardVisible];
    BOOL switcherIsHidden = !(_switcherIsVisible || [[%c(SBUIController) sharedInstance] isSwitcherShowing]);
    if (switcherIsHidden && !isInSpotlight) {
        CLog(@"Checking visibility for %@", icon.displayName);
        if ([[STKPreferences sharedPreferences] iconIsInStack:icon]) {
            isVisible = NO;
        }
        PARAMLOGC(@"%@", BOOL_TO_STRING(isVisible));
    }
    return isVisible;
}
%end

#pragma mark - SBUIController Hook
%hook SBUIController
- (BOOL)clickedMenuButton
{
    STKStack *activeStack = [STKStackController sharedInstance].activeStack;
    if (activeStack && ![(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication]) {
        BOOL manDidIntercept = [activeStack handleHomeButtonPress];
        if (!manDidIntercept) {
            [[STKStackController sharedInstance] closeActiveStack];
        }
        return YES;
    }
    else {
        return %orig();
    }
}

- (BOOL)_activateSwitcher:(NSTimeInterval)animationDuration
{
    if ([STKStackController sharedInstance].activeStack.isSelecting == NO) {
        [[STKStackController sharedInstance] closeActiveStack];
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

#pragma mark - SBAppSwitcherController Hook
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

#pragma mark - Compatibility Hooks
#pragma mark - Folder Enhancer Compatibility
%group FECompat
%hook FEGridFolderView
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [[STKStackController sharedInstance] closeActiveStack];
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

#pragma mark - SpringBoard Hook
%hook SpringBoard
- (void)_reportAppLaunchFinished
{
    %orig;

    if (![STKPreferences sharedPreferences].welcomeAlertShown) {
        NSDictionary *fields = @{(id)kCFUserNotificationAlertHeaderKey         : @"Apex",
                                 (id)kCFUserNotificationAlertMessageKey        : @"Thanks for purchasing!\nSwipe down on any app icon and tap the \"+\" to get started.",
                                 (id)kCFUserNotificationDefaultButtonTitleKey  : @"OK",
                                 (id)kCFUserNotificationAlternateButtonTitleKey: @"Settings"};

        SInt32 error = 0;
        CFUserNotificationRef notificationRef = CFUserNotificationCreate(kCFAllocatorDefault, 0, kCFUserNotificationNoteAlertLevel, &error, (CFDictionaryRef)fields);
        // Get and add a run loop source to the current run loop to get notified when the alert is dismissed
        CFRunLoopSourceRef runLoopSource = CFUserNotificationCreateRunLoopSource(kCFAllocatorDefault, notificationRef, STKWelcomeAlertCallback, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        if (error == 0) {
            [STKPreferences sharedPreferences].welcomeAlertShown = YES;
        }
    }
}
%end

static void STKWelcomeAlertCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags)
{
    if ((responseFlags & 0x3) == kCFUserNotificationAlternateResponse) {
        // Open settings to custom bundle
        [(SpringBoard *)[UIApplication sharedApplication] applicationOpenURL:[NSURL URLWithString:@"prefs:root="kSTKTweakName] publicURLsOnly:NO];
    }
    CFRelease(userNotification);
}

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        STKLog(@"Initializing");
        %init();

        dlopen("/Library/MobileSubstrate/DynamicLibraries/IconSupport.dylib", RTLD_NOW);
        [[%c(ISIconSupport) sharedInstance] addExtension:kSTKTweakName];

        void *feHandle = dlopen("/Library/MobileSubstrate/DynamicLibraries/FolderEnhancer.dylib", RTLD_NOW);
        if (feHandle) {
            %init(FECompat);
        }
        void *zephyrHandle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Zephyr.dylib", RTLD_NOW);
        if (zephyrHandle) {
            %init(ZephyrCompat);
        }
    }
}
