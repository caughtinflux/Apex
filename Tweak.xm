#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IconSupport/ISIconSupport.h>
#import <SpringBoard/SpringBoard.h>
#import <Search/SPSearchResultSection.h>
#import <Search/SPSearchResult.h>

#import "STKConstants.h"


#pragma mark - Wilkommen
static void STKWelcomeAlertCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags)
{
    if ((responseFlags & 0x3) == kCFUserNotificationAlternateResponse) {
        // Open settings to custom bundle
        [(SpringBoard *)[UIApplication sharedApplication] applicationOpenURL:[NSURL URLWithString:@"prefs:root="kSTKTweakName] publicURLsOnly:NO];
    }
    CFRelease(userNotification);
}

#pragma mark - SpringBoard
%hook SpringBoard
- (void)_reportAppLaunchFinished
{
    %orig;
    if (![STKPreferences sharedPreferences].welcomeAlertShown) {
        NSDictionary *fields = @{(id)kCFUserNotificationAlertHeaderKey: @"Apex",
                                 (id)kCFUserNotificationAlertMessageKey: @"Thanks for purchasing!\nSwipe down on any app icon and tap the \"+\" to get started.",
                                 (id)kCFUserNotificationDefaultButtonTitleKey: @"OK",
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

#pragma mark - SBIconController
%hook SBIconController
- (void)setIsEditing:(BOOL)editing
{
    BOOL stoppedEditing = ([self isEditing] && editing == NO);
    %orig(editing);
    if (stoppedEditing) {
        [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingEndedNotificationName object:nil];
    }
}

- (void)_closeFolderController:(SBFolderController *)folderController animated:(BOOL)animated withCompletion:(id)completion
{
    BOOL handled = [[STKGroupController sharedController] handleClosingEvent:STKClosingEventHomeButtonPress];
    if (!handled) {
        %orig();
    }
}

%end

#pragma mark - SBIconView
%hook SBIconView
- (void)setLocation:(SBIconLocation)location
{
    SBIconLocation previousLoc = self.location;
    %orig(location);
    STKGroupController *groupController = [STKGroupController sharedController];
    if ([self groupView] && previousLoc == location && self.delegate != groupController) {
        self.delegate = [STKGroupController sharedController];
        return;
    }
    if ([[%c(SBIconViewMap) homescreenMap] mappedIconViewForIcon:self.icon]
        && STKListViewForIcon(self.icon)
        && [self.icon isLeafIcon]
        && ![self.icon isDownloadingIcon]) {
        [[STKGroupController sharedController] addOrUpdateGroupViewForIconView:self];
    }
}
%end

#pragma mark - SBIconModel
%hook SBIconModel
- (BOOL)isIconVisible:(SBIcon *)icon
{
    BOOL isVisible = %orig(icon);
    if (![[%c(SBUIController) sharedInstance] isAppSwitcherShowing]
        && [[STKPreferences sharedPreferences] groupForSubappIcon:icon]) {
        isVisible = NO;
    }
    return isVisible;
}

- (SBDownloadingIcon *)addDownloadingIconForDownload:(SBApplicationPlaceholder *)download
{
    SBDownloadingIcon *downloadingIcon = %orig();
    SBIcon *icon = [self expectedIconForDisplayIdentifier:[downloadingIcon identifierForCorrespondingApplicationIcon]];
    [[STKGroupController sharedController] handleIconRemoval:icon];
    return downloadingIcon;
}

- (void)layout
{
    [[STKPreferences sharedPreferences] reloadPreferences];
    %orig();
}

- (void)removeIconForIdentifier:(NSString *)identifier
{
    SBIcon *icon = [self expectedIconForDisplayIdentifier:identifier];
    [[STKGroupController sharedController] handleIconRemoval:icon];
    %orig();
}
%end

#pragma mark - Search Agent Hook
%hook SPSearchAgent
- (id)sectionAtIndex:(NSUInteger)idx
{
    %orig();
    SPSearchResultSection *section = %orig();
    if (section.hasDomain && section.domain == 4) {
        for (SPSearchResult *result in section.results) {
            NSString *appID = result.url;
            SBIcon *icon = [[(SBIconController *)[%c(SBIconController) sharedInstance] model] expectedIconForDisplayIdentifier:appID];
            STKGroup *group = [[STKPreferences sharedPreferences] groupForSubappIcon:icon];
            if (group) {
                SBIcon *centralIcon = group.centralIcon;
                [result setAuxiliaryTitle:centralIcon.displayName];
                [result setAuxiliarySubtitle:centralIcon.displayName];
            }
        }
    }
    return section;
}
%end

#pragma mark - SBIconViewMap
#define IS_HS_MAP() (self == [[self class] homescreenMap])
%hook SBIconViewMap
- (void)_recycleIconView:(SBIconView *)iconView
{
    [[STKGroupController sharedController] removeGroupViewFromIconView:iconView]; 
    %orig();
}

- (SBIconView *)mappedIconViewForIcon:(SBIcon *)icon
{
    SBIconView *mappedView = %orig(icon);
    if (!mappedView && IS_HS_MAP() && [STKGroupController sharedController].openGroupView) {
        mappedView = [[STKGroupController sharedController].openGroupView subappIconViewForIcon:icon];
    }
    return mappedView;
}
%end

#pragma mark - Animator Hooks
%hook SBCenterIconZoomAnimator
- (void)_positionView:(SBIconView *)iconView forIcon:(SBIcon *)icon
{
    self.iconListView.stk_modifyDisplacedIconOrigin = YES;
    %orig();
    self.iconListView.stk_modifyDisplacedIconOrigin = NO;
}

- (void)_cleanupAnimation
{
    STKGroupView *openGroupView = [STKGroupController sharedController].openGroupView;
    SBIconListView *listView = STKListViewForIcon(openGroupView.group.centralIcon);
    if (openGroupView) {
        // If there is an open group view, the list view shouldn't reset the groups's displaced icons
        // to their original positions
        listView.stk_modifyDisplacedIconOrigin = YES;
    }
    %orig();
    listView.stk_modifyDisplacedIconOrigin = NO;
}
%end

%hook SBScaleIconZoomAnimator 
- (void)_prepareAnimation
{
    %orig();
    [self.targetIconView stk_setImageViewScale:1.0];
}

- (void)_cleanupAnimation
{
    [self.targetIconView.groupView resetImageViewScale];

    STKGroupView *openGroupView = [STKGroupController sharedController].openGroupView;
    SBIconListView *listView = STKListViewForIcon(openGroupView.group.centralIcon);
    if (openGroupView) {
        // If there is an open group view, the list view shouldn't reset the groups's displaced icons
        // to their original positions
        listView.stk_modifyDisplacedIconOrigin = YES;
    }
    %orig();
    listView.stk_modifyDisplacedIconOrigin = NO;
}

- (SBIconView *)iconViewForIcon:(SBIcon *)icon
{
    // SBIconZoomAnimator loves icon views, and can never let them go
    // let's make sure it doesn't feel heartbroken (i.e. failing assertions)
    SBIconView *iconView = %orig(icon);
    STKGroupView *openGroupView = ([STKGroupController sharedController].openGroupView ?: [STKGroupController sharedController].openingGroupView);
    iconView = [openGroupView subappIconViewForIcon:icon] ?: iconView;
    return iconView;
}
%end

#pragma mark - SBIconListView
%hook SBIconListView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    STKGroupController *controller = [STKGroupController sharedController];
    STKGroupView *activeGroupView = (controller.openGroupView ?: controller.openingGroupView);
    UIView *ret = %orig();

    if (activeGroupView) {
        // Send touches to the subapps in a group (since they are not within their superview's bounds)
        UIView *superview = [activeGroupView superview];
        CGPoint newPoint = [self convertPoint:point toView:superview];
        ret = [superview hitTest:newPoint withEvent:event];
    }   
    return ret;
}

- (void)performRotationWithDuration:(NSTimeInterval)duration
{
    [[STKGroupController sharedController] performRotationWithDuration:duration];
    %orig(duration);
}
%end

#pragma mark - SBFolderController
%hook SBFolderController
- (BOOL)_iconAppearsOnCurrentPage:(SBIcon *)icon
{
    // Folder animation expects the icon to be on the current page
    // However, it uses convoluted methods that I cbf about to check
    STKGroupView *groupView = [[%c(SBIconViewMap) homescreenMap] mappedIconViewForIcon:icon].containerGroupView;
    if (groupView) {
        icon = groupView.group.centralIcon;
    }
    return %orig(icon);
}
%end

#pragma mark - SBFolder
%hook SBFolder
- (SBIconListModel *)listContainingIcon:(SBIcon *)icon
{
    // this hook is only necessary when the open group's status is dirty.
    STKGroupView *groupView = [STKGroupController sharedController].openGroupView;
    if ((groupView.group.state == STKGroupStateDirty) && [[groupView.group.layout allIcons] containsObject:icon]) {
        return [self listContainingIcon:groupView.group.centralIcon];
    }
    return %orig(icon);
}
%end

#pragma mark - SBFolderView
%hook SBFolderView
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{    
    if (![STKGroupController sharedController].openingGroupView) {
        [[STKGroupController sharedController] handleClosingEvent:STKClosingEventListViewScroll];
    }
    %orig();
}
%end

#pragma mark - SBUIController
%hook SBUIController
- (BOOL)clickedMenuButton
{
    BOOL didReact = [[STKGroupController sharedController] handleClosingEvent:STKClosingEventHomeButtonPress];
    return (didReact ?: %orig());
}

- (BOOL)_activateAppSwitcherFromSide:(NSInteger)side
{
    [[STKGroupController sharedController] handleClosingEvent:STKClosingEventSwitcherActivation];
    return %orig(side);
}
%end

#pragma mark - SBLockScreenManager
%hook SBLockScreenManager
- (void)lockUIFromSource:(NSInteger)source withOptions:(id)options
{
    [[STKGroupController sharedController] handleClosingEvent:STKClosingEventLock];
    %orig();
}
%end

#pragma mark - SBSearchGesture
%hook SBSearchGesture
- (void)setEnabled:(BOOL)enabled
{
    if (enabled && [STKPreferences sharedPreferences].shouldDisableSearchGesture) {
        enabled = NO;
    }
    %orig(enabled);
}
%end

#pragma mark - UIStatusBar
%hook UIStatusBar
- (id)initWithFrame:(CGRect)frame
{
    if ((self = %orig())) {
        UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(stk_tapped:)];
        [self addGestureRecognizer:[recognizer autorelease]];
    }
    return self;
}

%new
- (void)stk_tapped:(UIPanGestureRecognizer *)recognizer
{
    [[STKGroupController sharedController] handleStatusBarTap];
}
%end

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        STKLog(@"Initializing");
        %init();
        dlopen("/Library/MobileSubstrate/DynamicLibraries/IconSupport.dylib", RTLD_NOW);
        dlopen("/Library/MobileSubstrate/DynamicLibraries/Gridlock.dylib", RTLD_NOW);
        dlopen("/Library/MobileSubstrate/DynamicLibraries/Bigify.dylib", RTLD_NOW);
        dlopen("/Library/MobileSubstrate/DynamicLibraries/Bigify+.dylib", RTLD_NOW);
        dlopen("/Library/MobileSubstrate/DynamicLibraries/Springtomize3.dylib", RTLD_NOW);
        dlopen("/Library/MobileSubstrate/DynamicLibraries/Infinidock.dylib", RTLD_NOW);
        dlopen("/Library/MobileSubstrate/DynamicLibraries/Infiniboard.dylib", RTLD_NOW);
        [[%c(ISIconSupport) sharedInstance] addExtension:kSTKTweakName@"DEBUG"];
    }
}
