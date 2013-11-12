#import "STKConstants.h"
#import "SBIconListView+ApexAdditions.h"
#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

NSString * const STKTweakName                  = @"Apex";
NSString * const STKPlaceholderIconIdentifier  = @"com.a3tweaks.apex.placeholderid";

CFStringRef const STKPrefsChangedNotificationName = CFSTR("com.a3tweaks.apex.prefschanged");

inline double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax)
{
    double oldRange = (prevMax - prevMin);
    double newRange = (newMax - newMin);
    return (((numToScale - prevMin) * newRange) / oldRange) + newMin;
}

inline double STKAlphaFromDistance(double distance, CGFloat targetDistance)
{
    double alpha = STKScaleNumber(distance, 0.0, targetDistance, 1.0, 0.0);
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
CGFloat STKGetCurrentTargetDistance(void)
{
    return _currentTargetDistance;
}

void STKUpdateTargetDistanceInListView(SBIconListView *listView, BOOL forDock)
{
    CGFloat defaultHeight = [objc_getClass("SBIconView") defaultIconSize].height;
    CGFloat verticalPadding = [listView stk_realVerticalIconPadding];
    _currentTargetDistance = (defaultHeight + verticalPadding);
    if (forDock) {
        _currentTargetDistance += ([[objc_getClass("SBIconController") sharedInstance] dock].frame.origin.y * 0.5); 
    }
}
