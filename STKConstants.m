#import "STKConstants.h"
#import "SBIconListView+ApexAdditions.h"
#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

NSString * const STKTweakName = @"Apex";
NSString * const STKEditingEndedNotificationName = @"STKEditingEnded";

CFStringRef const STKPrefsChangedNotificationName = CFSTR("com.a3tweaks.apex2.prefschanged");

SBIconListView * STKListViewForIcon(SBIcon *icon)
{
    SBIconController *controller = [objc_getClass("SBIconController") sharedInstance];
    SBRootFolder *rootFolder = [controller rootFolder];
    NSIndexPath *indexPath = [rootFolder indexPathForIcon:icon];    
    SBIconListView *listView = nil;
    [controller getListView:&listView folder:NULL relativePath:NULL forIndexPath:indexPath createIfNecessary:NO];

    return listView;
}

SBIconCoordinate STKCoordinateFromDictionary(NSDictionary *dict)
{
    return (SBIconCoordinate){[dict[@"row"] integerValue], [dict[@"col"] integerValue]};
}

NSDictionary * STKDictionaryFromCoordinate(SBIconCoordinate coordinate)
{
    return @{@"row":[NSNumber numberWithInteger:coordinate.row], @"col":[NSNumber numberWithInteger:coordinate.col]};
}

double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax)
{
    double oldRange = (prevMax - prevMin);
    double newRange = (newMax - newMin);
    return (((numToScale - prevMin) * newRange) / oldRange) + newMin;
}

NSString * NSStringFromSTKGroupSlot(STKGroupSlot slot)
{
    return [NSString stringWithFormat:@"%@, index: %@", NSStringFromLayoutPosition(slot.position), @(slot.index)];
}

