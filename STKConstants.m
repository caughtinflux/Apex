#import "STKConstants.h"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIconListView.h>
#import <SpringBoard/SBRootFolder.h>

#import <objc/runtime.h>


NSString * const STKTweakName = @"Stacks";
NSString * const STKEditingStateChangedNotification = @"STKEditingStateChanged";
NSString * const STKHomescreenWillScrollNotification = @"STKHomescreenWillScrollNotification";

double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax)
{
	double oldRange = (prevMax - prevMin);
	double newRange = (newMax - newMin);
	return (((numToScale - prevMin) * newRange) / oldRange) + newMin;
}

double STKAlphaFromDistance(double distance)
{
	// Subtract from 1 to invert the scale
	// Greater the distance, lower the alpha
	return  fabs(0.6 - (STKScaleNumber(distance, 0.0, 20.0, 0.4, 1.0)));
}

extern SBIconListView * STKListViewForIcon(SBIcon *icon)
{
	SBIconController *controller = [objc_getClass("SBIconController") sharedInstance];
	
	SBRootFolder *rootFolder = [controller valueForKeyPath:@"rootFolder"];
	NSIndexPath *indexPath = [rootFolder indexPathForIcon:icon];
	
	SBIconListView *listView = nil;
	[controller getListView:&listView folder:NULL relativePath:NULL forIndexPath:indexPath createIfNecessary:YES];

	return listView;
}
