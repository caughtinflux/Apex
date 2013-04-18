#import "STKConstants.h"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIconListView.h>
#import <SpringBoard/SBRootFolder.h>

#import <objc/runtime.h>


NSString * const STKTweakName = @"Stacks";
NSString * const STKEditingStateChangedNotification = @"STKEditingStateChanged";

double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax)
{
	double ret = ((numToScale - prevMin) * (newMax - newMin)) \
			  /*-------------------------------------------------*/ /\
				      ((prevMax - prevMin) + newMin);

	return ret;
}

double STKAlphaFromDistance(double distance)
{
	// Subtract from 1 to invert the scale
	// Greater the distance, lower the alpha
	return (STKScaleNumber(distance, 0.0, 10, 0.0, 1.0));
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
