#import "STKConstants.h"
#import "SBIconListView+ApexAdditions.h"
#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

NSString * const STKTweakName                  = @"Apex";
NSString * const STKPlaceholderIconIdentifier  = @"com.a3tweaks.apex.placeholderid";

CFStringRef const STKPrefsChangedNotificationName = CFSTR("com.a3tweaks.apex.prefschanged");

SBIconListView * STKListViewForIcon(SBIcon *icon)
{
    SBIconController *controller = [objc_getClass("SBIconController") sharedInstance];
    SBRootFolder *rootFolder = [controller valueForKeyPath:@"rootFolder"];
    NSIndexPath *indexPath = [rootFolder indexPathForIcon:icon];    
    SBIconListView *listView = nil;
    [controller getListView:&listView folder:NULL relativePath:NULL forIndexPath:indexPath createIfNecessary:YES];

    return listView;
}

inline SBIconCoordinate STKCoordinateFromDictionary(NSDictionary *dict)
{
    return (SBIconCoordinate){[dict[@"row"] integerValue], [dict[@"col"] integerValue]};
}

inline NSDictionary * STKDictionaryFromCoordinate(SBIconCoordinate coordinate)
{
    return @{@"row":[NSNumber numberWithInteger:coordinate.row], @"col":[NSNumber numberWithInteger:coordinate.col]};
}
