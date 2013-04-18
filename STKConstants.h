#ifndef STK_CONSTANTS_H
#define STK_CONSTANTS_H

#ifdef DEBUG
	#define DLog(fmt, ...) NSLog((@"STK: %s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
	#define CLog(fmt, ...) NSLog((@"STK: " fmt), ##__VA_ARGS__)
#else
	#define DLog(...)
	#define CLog(...)
#endif

@class NSString, SBIconListView, SBIcon;

extern NSString * const STKTweakName;
extern NSString * const STKEditingStateChangedNotification;

#define PREFS_PATH [NSString stringWithFormat:@"%@/Library/Preferences/com.a3tweaks.%@.plist", STKTweakName];

#define EXECUTE_BLOCK_AFTER_DELAY(delayInSeconds, block) (dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block))

// Function to translate a number from one range to another
// For instance 248 in the range [0, 320] -> something 0.0 -> 0.1
extern double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax);

// Wrapper function
extern double STKAlphaFromDistance(double distance);

extern SBIconListView * STKListViewForIcon(SBIcon *icon);

#endif
