#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>
#import "STKConstants.h"

%hook SBFolderIcon

- (Class)iconViewClassForLocation:(SBIconLocation)loc
{
	if ([[self folder] isApexFolder]) {
		return objc_getClass("STKFolderIconView");
	}
	else {
		return %orig();
	}
}

%end

%hook SBFolderIconView

- (void)setIcon:(SBFolderIcon *)icon
{
	%orig();
	if ([icon.folder isApexFolder]) {
		// perform Apex Haxx
	}
}

%new
- (void)performModificationsForApex
{

}

%end
