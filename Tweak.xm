#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IconSupport/ISIconSupport.h>
#import <SpringBoard/SpringBoard.h>
#import <Search/SPSearchResultSection.h>
#import <Search/SPSearchResult.h>
#import "SBIconViewMap+ApexAdditions.h"
#import "STKConstants.h"

@interface SpringBoard (ApexWelcome)
- (void)stk_showWelcomeAlert;
@end

#pragma mark - Wilkommen
static void STKWelcomeAlertCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags)
{
    if ((responseFlags & 0x3) == kCFUserNotificationAlternateResponse) {
        // Open settings to custom bundle
        [(SpringBoard *)[UIApplication sharedApplication] applicationOpenURL:[NSURL URLWithString:@"prefs:root="kSTKPrefsRootName]];
    }
    CFRelease(userNotification);
}

#pragma mark - SpringBoard
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)app
{
    %orig();
    [self stk_showWelcomeAlert];
}

%new
- (void)stk_showWelcomeAlert
{
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

// 7.0
- (void)_closeFolderController:(id)controller animated:(BOOL)animated
{
    BOOL handled = [[STKGroupController sharedController] handleClosingEvent:STKClosingEventHomeButtonPress];
    if (!handled) {
        %orig();
    }
}

- (void)_handleShortcutMenuPeek:(UILongPressGestureRecognizer *)recognizer
{
    SBIconView *iconView = (SBIconView *)recognizer.view;
    if (![iconView isKindOfClass:[%c(SBIconView) class]]) {
        return;
    }
    STKGroupView *groupView = [iconView groupView];
    if (recognizer.state == UIGestureRecognizerStateBegan && groupView != nil) {
        CGPoint location = [recognizer locationInView:groupView];
        SBIconView *iconViewAtTouchLocation = (SBIconView *)[groupView hitTest:location withEvent:nil];
        if (iconView == iconViewAtTouchLocation) {
            if ([self respondsToSelector:@selector(_revealMenuForIconView:presentImmediately:)]) {
                [self _revealMenuForIconView:iconViewAtTouchLocation presentImmediately:NO];
            }
            else if ([self respondsToSelector:@selector(_revealMenuForIconView:)]) {
                [self _revealMenuForIconView:iconViewAtTouchLocation];
            }
            return;
        }
    }
    else  {
        %orig();
    }
}

%end

#pragma mark - SBFolderController
%hook SBRootFolderController
- (BOOL)setCurrentPageIndexToListContainingIcon:(SBIcon *)icon animated:(BOOL)animated {
    STKGroupView *currentGroupView = [STKGroupController sharedController].activeGroupView;
    if ([currentGroupView.group.layout containsIcon:icon]) {
        return YES;
    }
    return %orig();
}
%end

#pragma mark
%hook SBIconView
- (void)setLocation:(SBIconLocation)location
{
    SBIconLocation previousLoc = self.location;
    %orig(location);
    STKGroupController *groupController = [STKGroupController sharedController];
    if ([self groupView] && (previousLoc == location) && (self.delegate != groupController)) {
        self.delegate = [STKGroupController sharedController];
        return;
    }
    if ([[%c(SBIconViewMap) stk_homescreenMap] mappedIconViewForIcon:self.icon]
        && STKListViewForIcon(self.icon)
        && [self.icon isLeafIcon]
        && ![self.icon isDownloadingIcon]) {
        [[STKGroupController sharedController] addOrUpdateGroupViewForIconView:self];
    }
}

%new
- (void)iconImageDidUpdate:(SBIcon *)icon
{
    [(self.groupView ?: self.containerGroupView) resetLayouts];
}
%end

#pragma mark - SBIconListModel
%hook SBIconListModel
- (BOOL)addIcon:(SBIcon *)icon asDirty:(BOOL)dirty
{
    if ([[STKPreferences sharedPreferences] groupForSubappIcon:icon]) {
        return NO;
    }
    return %orig();
}

- (id)insertIcon:(SBIcon *)icon atIndex:(NSUInteger *)insertionIndex
{
    if ([[STKPreferences sharedPreferences] groupForSubappIcon:icon]) {
        return nil;
    }
    return %orig();
}
%end

#pragma mark - SBIconModel
%hook SBIconModel
- (void)layout
{
    [[STKPreferences sharedPreferences] reloadPreferences];
    %orig();
    [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingEndedNotificationName object:nil];
}

- (void)removeIconForIdentifier:(NSString *)identifier
{
    SBIcon *icon = [self expectedIconForDisplayIdentifier:identifier];
    [[STKGroupController sharedController] handleIconRemoval:icon];
    %orig();
}

- (void)removeIcon:(SBIcon *)icon
{
    [[icon retain] autorelease];
    %orig();
    if ([icon isDownloadingIcon]) {
        NSString *appIconIdent;
        if ([icon respondsToSelector:@selector(identifierForCorrespondingApplicationIcon)]) {
            appIconIdent = [(SBDownloadingIcon *)icon identifierForCorrespondingApplicationIcon];
        }
        else {
            appIconIdent = [(SBDownloadingIcon *)icon applicationBundleID];
        }
        SBApplicationIcon *applicationIcon = nil;
        if (IS_8_1()) {
            applicationIcon = [self applicationIconForBundleIdentifier:appIconIdent];
        }
        else {
            applicationIcon = [self applicationIconForDisplayIdentifier:appIconIdent];
        }
        if (![applicationIcon activeDataSource]) {
            SEL identSel = (IS_8_1() ? @selector(applicationWithBundleIdentifier:) : @selector(applicationWithDisplayIdentifier:));
            SBApplication *app = [[CLASS(SBApplicationController) sharedInstance] performSelector:identSel withObject:appIconIdent];
            [applicationIcon addIconDataSource:app];
        }
    }
}

%end

#pragma mark - Search Agent Hook
%hook SPSearchAgent
- (id)sectionAtIndex:(NSUInteger)idx
{
    %orig();
    SPSearchResultSection *section = %orig();

    NSUInteger domain = (IS_9_0() ? SPSearchResultDomainTopHits : 4);
    if (section.domain == domain) {
        for (SPSearchResult *result in section.results) {
            NSString *appID = result.url;
            SBIcon *icon = [[(SBIconController *)[%c(SBIconController) sharedInstance] model] expectedIconForDisplayIdentifier:appID];
            STKGroup *group = [[STKPreferences sharedPreferences] groupForSubappIcon:icon];
            if (group) {
                SBIcon *centralIcon = group.centralIcon;
                if ([centralIcon respondsToSelector:@selector(displayNameForLocation:)]) {
                    if (IS_9_0()) {
                        result.subtitle = [centralIcon displayNameForLocation:SBIconLocationHomeScreen];
                    }
                    else {
                        result.auxiliaryTitle = [centralIcon displayNameForLocation:SBIconLocationHomeScreen];
                    }
                }
                else {
                    result.auxiliaryTitle = centralIcon.displayName;
                }
            }
        }
    }
    return section;
}
%end

#pragma mark - SBIconViewMap
#define IS_HS_MAP() (self == [[self class] stk_homescreenMap])
%hook SBIconViewMap
- (void)_recycleIconView:(SBIconView *)iconView
{
    if (IS_HS_MAP()) {
        [[STKGroupController sharedController] removeGroupViewFromIconView:iconView];
    }
    %orig();
}

- (SBIconView *)mappedIconViewForIcon:(SBIcon *)icon
{
    SBIconView *mappedView = %orig(icon);
    if (!mappedView && IS_HS_MAP() && [STKGroupController sharedController].openGroupView) {
        if ([STKGroupController sharedController].openGroupView.group.state != STKGroupStateDirty) {
            // I don't know what I meant to do here.
            // Whoops?
        }
    }
    return mappedView;
}

- (SBIconView *)extraIconViewForIcon:(SBIcon *)icon
{
    auto iconView = %orig();
    // on iOS 10, this returns `nil` for icons that return `YES` from `isPlaceholder`, which our placeholder icon (STKPlaceholderIcon) does
    // The SBScaleIconZoomAnimator.targetIconView needs this hack to work
    if (!iconView && IS_10_0() && [icon isKindOfClass:%c(STKPlaceholderIcon)]) {
        iconView = [[STKGroupController sharedController].iconViewRecycler iconViewForIcon:icon];
    }
    return iconView;
}

%end

#pragma mark - Animator Hooks
%hook SBCenterIconZoomAnimator
- (void)_prepareAnimation
{
    %orig();
    [self enumerateIconsAndIconViewsWithHandler:^(SBIcon *icon, SBIconView *iv) {
        iv.layer.shouldRasterize = YES;
    }];
}

- (void)_positionView:(SBIconView *)iconView forIcon:(SBIcon *)icon
{
    self.iconListView.stk_modifyDisplacedIconOrigin = YES;
    %orig();
    self.iconListView.stk_modifyDisplacedIconOrigin = NO;
}

- (void)_cleanupAnimation
{
    [self enumerateIconsAndIconViewsWithHandler:^(SBIcon *icon, SBIconView *iv) {
        iv.layer.shouldRasterize = NO;
    }];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [[STKGroupController sharedController] handleClosingEvent:STKClosingEventLock];
    });
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
- (void)setDisabled:(BOOL)disabled forReason:(NSString *)reason
{
    if (!disabled && [STKPreferences sharedPreferences].shouldDisableSearchGesture) {
        disabled = YES;
    }
    %orig(disabled, reason);
}

%new
- (void)stk_setEnabled:(BOOL)enabled
{
    if ([self respondsToSelector:@selector(setEnabled:)]) {
        [self setEnabled:enabled];
    }
    else if ([self respondsToSelector:@selector(setDisabled:forReason:)]) {
        [self setDisabled:!enabled forReason:@"Apex!"];
    }
}

%end

#pragma mark - UIStatusBar
%hook UIStatusBar
static STKStatusBarRecognizerDelegate *_recognizerDelegate;
- (id)initWithFrame:(CGRect)frame
{
    if ((self = %orig())) {
        UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(stk_tapped:)];
        [self addGestureRecognizer:[recognizer autorelease]];
        if (!_recognizerDelegate) {
            _recognizerDelegate = [[STKStatusBarRecognizerDelegate alloc] init];
            recognizer.cancelsTouchesInView = NO;
        }
        recognizer.delegate = _recognizerDelegate;
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
        dlopen("/Library/MobileSubstrate/DynamicLibraries/labelnotify.dylib", RTLD_NOW);
        STKLog(@"Initializing");
        [[%c(ISIconSupport) sharedInstance] addExtension:kSTKTweakName];
        %init();
    }
}
