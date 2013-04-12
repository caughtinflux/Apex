#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "STKConstants.h"

#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIcon.h>
#import <SpringBoard/SBIconModel.h>
#import <SpringBoard/SBIconViewMap.h>
#import <SpringBoard/SBIconView.h>
#import <SpringBoard/SBIconListView.h>


#pragma mark - Variables



#pragma mark - SBIconView
%hook SBIconView

- (void)setIcon:(SBIcon *)icon
{
	%orig(icon);
}

%end


#pragma mark - Constructor
%ctor
{
	%init();
}
