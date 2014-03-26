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

%end

#pragma mark - SBIconView
%hook SBIconView
- (void)setLocation:(SBIconLocation)location
{
    SBIconLocation previousLoc = self.location;
    %orig(location);

    if ([STKListViewForIcon(self.icon) isKindOfClass:CLASS(SBFolderIconListView)]) {
        [[STKGroupController sharedController] removeGroupViewFromIconView:self];
        return;
    }
    if ([self groupView] && previousLoc == location) {
        self.delegate = [STKGroupController sharedController];
        return;
    }
    if ([[%c(SBIconViewMap) homescreenMap] mappedIconViewForIcon:self.icon]
        && [self.superview isKindOfClass:%c(SBIconListView)]
        && STKListViewForIcon(self.icon)
        && [self.icon isLeafIcon]
        && ![self.icon isDownloadingIcon]) {
        [[STKGroupController sharedController] addGroupViewToIconView:self];
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
%end

#pragma mark - Search Agent Hook
%hook SPSearchAgent
- (id)sectionAtIndex:(NSUInteger)idx
{
    %orig();
    SPSearchResultSection *section = %orig();
    if (section.hasDomain && section.domain == 4) {
        SPSearchResult *result = [section.results firstObject];
        NSString *appID = result.url;
        SBIcon *icon = [[(SBIconController *)[%c(SBIconController) sharedInstance] model] expectedIconForDisplayIdentifier:appID];
        STKGroup *group = [[STKPreferences sharedPreferences] groupForSubappIcon:icon];
        if (group) {
            SBIcon *centralIcon = group.centralIcon;
            [result setAuxiliaryTitle:centralIcon.displayName];
            [result setAuxiliarySubtitle:centralIcon.displayName];
        }
    }
    return section;
}
%end

/***********************************************************************************************************
************************************ (Mostly) Hooks For Zoom Animator **************************************
************************************************************************************************************
************************************************************************************************************/
#pragma mark - SBIconViewMap
%hook SBIconViewMap
- (void)_recycleIconView:(SBIconView *)iconView
{
    [[STKGroupController sharedController] removeGroupViewFromIconView:iconView];
    %orig();
}

- (SBIconView *)mappedIconViewForIcon:(SBIcon *)icon
{
    SBIconView *mappedView = %orig(icon);
    if (!mappedView && (self == [[self class] homescreenMap]) && [STKGroupController sharedController].openGroupView) {
        mappedView = [[STKGroupController sharedController].openGroupView subappIconViewForIcon:icon];
    }
    return mappedView;
}
%end

%hook SBCenterIconZoomAnimator
- (void)_positionView:(SBIconView *)iconView forIcon:(SBIcon *)icon
{
    if ([STKGroupController sharedController].openGroupView) {
        // Don't let the animator screw with the displaced icons
        return;
    }
    %orig();
}
%end

#pragma mark - SBIconZoomAnimator
%hook SBScaleIconZoomAnimator
- (SBIconView *)iconViewForIcon:(SBIcon *)icon
{
    // SBIconZoomAnimator loves icon views, and can never let them go
    // let's make sure it doesn't feel heartbroken (i.e. failing assertions)
    SBIconView *iconView = %orig(icon);
    STKGroupView *openGroupView = [STKGroupController sharedController].openGroupView;
    iconView = [openGroupView subappIconViewForIcon:icon] ?: iconView;
    return iconView;
}

%end

#pragma mark - SBIconListView 
%hook SBIconListView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    STKGroupView *openGroupView = [[STKGroupController sharedController] openGroupView];
    UIView *ret = %orig();
    if (openGroupView) {
        UIView *superview = [openGroupView superview];
        CGPoint newPoint = [self convertPoint:point toView:superview];
        ret = [superview hitTest:newPoint withEvent:event];
    }
    return ret;
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
    [[STKGroupController sharedController] handleClosingEvent:STKClosingEventListViewScroll];   
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
%end

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        STKLog(@"Initializing");
        %init();
        dlopen("/Library/MobileSubstrate/DynamicLibraries/IconSupport.dylib", RTLD_NOW);
        [[%c(ISIconSupport) sharedInstance] addExtension:kSTKTweakName@"DEBUG"];
    }
}
