#import "STKConstants.h"

#import <UIKit/UIKit.h>

#import <SpringBoard/SpringBoard.h>

#import <objc/runtime.h>
#import <sys/sysctl.h>

NSString * const STKTweakName                       = @"Acervos";
NSString * const STKEditingStateChangedNotification = @"STKEditingStateChanged";
NSString * const STKStackClosingEventNotification   = @"STKStackClosingEvent";
NSString * const STKPlaceHolderIconIdentifier       = @"com.a3tweaks.placeholderid";

CFStringRef const STKPrefsChangedNotificationName = CFSTR("com.a3tweaks.acervos.prefschanged");

// SpringBoard constants
NSString * const SBLockStateChangeNotification = @"com.apple.springboard.lockstate";

inline double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax)
{
    double oldRange = (prevMax - prevMin);
    double newRange = (newMax - newMin);
    return (((numToScale - prevMin) * newRange) / oldRange) + newMin;
}

inline double STKAlphaFromDistance(double distance)
{
    // Greater the distance, lower the alpha, therefore, switch places for newMax and newMin
    double alpha = (STKScaleNumber(distance, 0.0, STKGetCurrentTargetDistance(), 1.0, 0.0));
    if (alpha < 0.0) {
        alpha = 0.0;
    }
    return alpha;
}

SBIconListView * STKListViewForIcon(SBIcon *icon)
{
    SBIconController *controller = [objc_getClass("SBIconController") sharedInstance];
    
    SBRootFolder *rootFolder = [controller valueForKeyPath:@"rootFolder"];
    NSIndexPath *indexPath = [rootFolder indexPathForIcon:icon];
    
    SBIconListView *listView = nil;
    [controller getListView:&listView folder:NULL relativePath:NULL forIndexPath:indexPath createIfNecessary:YES];

    return listView;
}

static CGFloat _currentTargetDistance;
inline CGFloat STKGetCurrentTargetDistance(void)
{
    return _currentTargetDistance;
}

inline void STKUpdateTargetDistanceInListView(SBIconListView *listView)
{
    CGPoint referencePoint = [listView originForIconAtX:2 Y:2];
    CGPoint verticalOrigin = [listView originForIconAtX:2 Y:1];
    
    CGFloat verticalDistance = referencePoint.y - verticalOrigin.y;

    _currentTargetDistance = verticalDistance;
}
