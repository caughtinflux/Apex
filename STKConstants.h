#ifndef STK_CONSTANTS_H
#define STK_CONSTANTS_H

#ifdef DEBUG
	#define DLog(fmt, ...) NSLog((@"STK: %s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
	#define CLog(fmt, ...) NSLog((@"STK: " fmt), ##__VA_ARGS__)
#else
	#define DLog(...)
	#define CLog(...)
#endif

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGBase.h>

#define kPrefPath [NSString stringWithFormat:@"%@/Library/Preferences/com.a3tweaks.%@.plist", NSHomeDirectory(), STKTweakName];

#define EXECUTE_BLOCK_AFTER_DELAY(delayInSeconds, block) (dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block))

#define kTargetDistance ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) ? 76.0f : 176.0f)

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
