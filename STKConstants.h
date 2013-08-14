#ifndef STK_CONSTANTS_H
#define STK_CONSTANTS_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGBase.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreFoundation/CFUserNotification.h>

#import "STKVersion.h"

#define kSTKTweakName @"Acervos"

#ifdef DEBUG
    #define DLog(fmt, ...) NSLog((@"[%@] %s [Line %d] " fmt), kSTKTweakName, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
    #define CLog(fmt, ...) NSLog((@"[%@] " fmt), kSTKTweakName, ##__VA_ARGS__)
#else
    #define DLog(...)
    #define CLog(...)
#endif

#define BOOL_TO_STRING(b) (b ? @"YES" : @"NO")


#define kPrefPath [NSString stringWithFormat:@"%@/Library/Preferences/%@/com.a3tweaks.%@.plist", kSTKTweakName, NSHomeDirectory(), kSTKTweakName]

#define kCentralIconPreviewScale 0.95f
#define kStackPreviewIconScale   0.81f

#define EXECUTE_BLOCK_AFTER_DELAY(delayInSeconds, block) (dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block))

#define SHOW_USER_NOTIFICATION(_title, _message, _dismissButtonTitle) \
                               NSDictionary *fields = @{(id)kCFUserNotificationAlertHeaderKey        : _title, \
                                                        (id)kCFUserNotificationAlertMessageKey       : _message, \
                                                        (id)kCFUserNotificationDefaultButtonTitleKey : _dismissButtonTitle}; \
                               CFUserNotificationRef notificationRef = CFUserNotificationCreate(kCFAllocatorDefault, 0, kCFUserNotificationNoteAlertLevel, NULL, (CFDictionaryRef)fields); \
                               CFRelease(notificationRef)


#define ICONID_HAS_STACK(ID) ([[[STKPreferences sharedPreferences] identifiersForIconsWithStack] containsObject:ID])
#define ICON_HAS_STACK(icon) ICONID_HAS_STACK(icon.leafIdentifier)

#define PATH_TO_IMAGE(_name) [[NSBundle bundleWithPath:@"/Library/Application Support/Acervos.bundle"] pathForResource:_name ofType:@"png"]
#define UIIMAGE_NAMED(_name) [[[UIImage alloc] initWithContentsOfFile:PATH_TO_IMAGE(_name)] autorelease]

#define MAP(_array, _block) for (id elem in _array) { _block(elem); }

@class NSString, SBIconListView, SBIcon;

#ifdef __cplusplus 
extern "C" {
#endif
    
    extern NSString * const STKEditingStateChangedNotification;
    extern NSString * const STKStackClosingEventNotification; // This notification is posted when something happens to make the stack close
    extern NSString * const STKPlaceHolderIconIdentifier;
    
    extern NSString * const SBLockStateChangeNotification;

    // Function to translate a number from one range to another
    // For instance 248 in the range [0, 320] -> something 0.0 -> 0.1
    extern inline double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax);

    // Wrapper functions
    extern inline double STKAlphaFromDistance(double distance);

    extern SBIconListView * STKListViewForIcon(SBIcon *icon);

    extern inline CGFloat STKGetCurrentTargetDistance(void);
    extern inline void    STKUpdateTargetDistanceInListView(SBIconListView *listView);

#ifdef __cplusplus 
}
#endif

#endif
