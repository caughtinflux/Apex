#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IconSupport/ISIconSupport.h>
#import <SpringBoard/SpringBoard.h>
#import <Search/SPSearchResultSection.h>

#import "STKGroupLayoutHandler.h"
#import "STKGroupLayout.h"
#import "STKGroup.h"
#import "STKGroupView.h"

#pragma mark - Function Declarations
%hook SpringBoard
- (void)_reportAppLaunchFinished
{
    %orig();
    %log();
    SBIcon *icon = [[(SBIconController *)[CLASS(SBIconController) sharedInstance] model] expectedIconForDisplayIdentifier:@"com.apple.weather"];
    
    SBIconListView *listView = [[%c(SBIconController) sharedInstance] currentRootIconList];
    STKGroupLayout *layout = [STKGroupLayoutHandler layoutForIcons:[listView.icons subarrayWithRange:NSMakeRange(0, 4)] aroundIconAtLocation:0];
    STKGroup *group = [[STKGroup alloc] initWithCentralIcon:icon layout:layout];
    STKGroupView *groupView = [[STKGroupView alloc] initWithGroup:group];
    groupView = nil;
    
}
%end

/*

static void STKWelcomeAlertCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags);

#pragma mark - SpringBoard Hook
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
*/

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        STKLog(@"Initializing");
        %init();
        // [[STKPreferences sharedPreferences] reloadPreferences];

        dlopen("/Library/MobileSubstrate/DynamicLibraries/IconSupport.dylib", RTLD_NOW);
        [[%c(ISIconSupport) sharedInstance] addExtension:kSTKTweakName];

       /* void *feHandle = dlopen("/Library/MobileSubstrate/DynamicLibraries/FolderEnhancer.dylib", RTLD_NOW);
        if (feHandle) {
            %init(FECompat);
        }
        void *zephyrHandle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Zephyr.dylib", RTLD_NOW);
        if (zephyrHandle) {
            %init(ZephyrCompat);
        }
        */
    }
}
