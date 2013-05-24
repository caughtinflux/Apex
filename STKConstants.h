#ifndef STK_CONSTANTS_H
#define STK_CONSTANTS_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGBase.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreFoundation/CFUserNotification.h>

#import "STKVersion.h"

#ifdef DEBUG
    #define DLog(fmt, ...) NSLog((@"STK: %s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
    #define CLog(fmt, ...) NSLog((@"STK: " fmt), ##__VA_ARGS__)
#else
    #define DLog(...)
    #define CLog(...)
#endif

#define BOOL_TO_STRING(b) (b ? @"YES" : @"NO")

#define kPrefPath [NSString stringWithFormat:@"%@/Library/Preferences/Acervos/com.a3tweaks.%@.plist", NSHomeDirectory(), STKTweakName]
#define kTargetDistance ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) ? 76.0f : 176.0f)


#define EXECUTE_BLOCK_AFTER_DELAY(delayInSeconds, block) (dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block))

#define SHOW_USER_NOTIFICATION(title, message, dismissButtonTitle) \
                               NSDictionary *fields = @{(id)kCFUserNotificationAlertHeaderKey        : title, \
                                                        (id)kCFUserNotificationAlertMessageKey       : message, \
                                                        (id)kCFUserNotificationDefaultButtonTitleKey : dismissButtonTitle}; \
                               CFUserNotificationRef notificationRef = CFUserNotificationCreate(kCFAllocatorDefault, 0, kCFUserNotificationNoteAlertLevel, NULL, (CFDictionaryRef)fields); \
                               CFRelease(notificationRef)


#define ICONID_HAS_STACK(ID) ([[[STKPreferences sharedPreferences] identifiersForIconsWithStack] containsObject:ID])
#define ICON_HAS_STACK(icon) ICONID_HAS_STACK(icon.leafIdentifier)

@class NSString, SBIconListView, SBIcon;

#ifdef __cplusplus 
extern "C" {
#endif

    extern NSString * const STKTweakName;
    extern NSString * const STKEditingStateChangedNotification;
    extern NSString * const STKStackClosingEventNotification; // This notification is posted when something happens to make the stack close
    
    extern NSString * const SBLockStateChangeNotification;

    // Function to translate a number from one range to another
    // For instance 248 in the range [0, 320] -> something 0.0 -> 0.1
    extern inline double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax);

    // Wrapper functions
    extern inline double __attribute__((overloadable)) STKAlphaFromDistance(double distance);
    extern inline double __attribute__((overloadable)) STKAlphaFromDistance(double distance, BOOL isGhostly);

    extern SBIconListView * STKListViewForIcon(SBIcon *icon);

    extern CGFloat STKGetCurrentTargetDistance(void);
    extern void    STKUpdateTargetDistanceInListView(SBIconListView *listView);

    extern NSUInteger STKGetCPUFrequency(void);

#ifdef __cplusplus 
}
#endif

#endif
