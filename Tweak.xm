#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <SpringBoard/SpringBoard.h>
#import <Search/SPSearchResultSection.h>

#pragma mark - Function Declarations
static void STKWelcomeAlertCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags);

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
        [[STKPreferences sharedPreferences] reloadPreferences];

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
