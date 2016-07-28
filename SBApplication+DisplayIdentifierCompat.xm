#import <SpringBoard/SpringBoard.h>
#import "STKConstants.h"

%group DisplayIdentifier_Compat
%hook SBApplication
%new
- (NSString *)displayIdentifier
{
	return [self bundleIdentifier];
}
%end
%end

%ctor
{
	if (![%c(SBApplication) instancesRespondToSelector:@selector(displayIdentifier)]) {
		%init(DisplayIdentifier_Compat);
	}
}
