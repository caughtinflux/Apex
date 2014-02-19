#ifndef STK_CONSTANTS_H
#define STK_CONSTANTS_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGBase.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreFoundation/CFUserNotification.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

#import "STKTypes.h"
#import "STKVersion.h"

#import "STKGroup.h"
#import "STKGroupView.h"
#import "STKGroupLayout.h"
#import "STKGroupLayoutHandler.h"
#import "STKGroupController.h"

#import "STKOverlayIcons.h"
#import "STKiconOverlayView.h"
#import "STKSelectionView.h"
#import "STKGroupSelectionAnimator.h"

#import "SBIconView+Apex.h"
#import "SBIconListView+ApexAdditions.h"

#import "STKPreferences.h"

#define kSTKTweakName @"Apex"

#ifdef DEBUG
    #define DLog(fmt, ...) NSLog((@"[%@] %s [Line %d] " fmt), kSTKTweakName, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
    #define CLog(fmt, ...) NSLog((@"[%@] " fmt), kSTKTweakName, ##__VA_ARGS__)
    #define VLog(_formatString, _param, ...) CLog(@"%s = "_formatString, #_param, _param, ##__VA_ARGS__)
#else
    #define DLog(...)
    #define CLog(...)
    #define VLog(...)
#endif

#define STKLog(fmt, ...) NSLog((@"[" kSTKTweakName @"] " fmt), ##__VA_ARGS__)
#define kPrefPath [NSString stringWithFormat:@"%@/Library/Preferences/com.a3tweaks."kSTKTweakName@".plist", NSHomeDirectory()]
#define PATH_TO_IMAGE(_name) [[NSBundle bundleWithPath:@"/Library/Application Support/Apex.bundle"] pathForResource:_name ofType:@"png"]
#define UIIMAGE_NAMED(_name) [[[UIImage alloc] initWithContentsOfFile:PATH_TO_IMAGE(_name)] autorelease]

#define EXECUTE_BLOCK_AFTER_DELAY(delayInSeconds, block) (dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block))

#undef CLASS
#define CLASS(cls) NSClassFromString(@#cls)

#ifdef __cplusplus 
extern "C" {
#endif
    extern NSString * const STKPlaceholderIconIdentifier;
    extern CFStringRef const STKPrefsChangedNotificationName;
    
    extern SBIconListView * STKListViewForIcon(SBIcon *icon);

    extern inline SBIconCoordinate STKCoordinateFromDictionary(NSDictionary *dict);
    extern inline NSDictionary * STKDictionaryFromCoordinate(SBIconCoordinate coordinate);
#ifdef __cplusplus 
}
#endif


#endif // STK_CONSTANTS_H
