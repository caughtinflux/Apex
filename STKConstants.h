#ifndef STK_CONSTANTS_H
#define STK_CONSTANTS_H

#ifdef DEBUG
	#define DLog(fmt, ...) NSLog((@"STK: %s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
	#define CLog(fmt, ...) NSLog((@"STK: " fmt), ##__VA_ARGS__)
#else
	#define DLog(...)
	#define CLog(...)
#endif

@class NSString;
extern NSString * const STKTweakName;

#define PREFS_PATH [NSString stringWithFormat:@"%@/Library/Preferences/com.a3tweaks.%@.plist"];

#endif
