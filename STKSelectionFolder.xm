#import "STKSelectionFolder.h"
#import "STKConstants.h"

%subclass SBFolder

%new
+ (id)sharedInstance
{
	static dispatch_once_t predicate;
	static id __si;
	dispatch_once(&predicate, ^{
		__si = [[self alloc] init];
	});
	return __si;
}

%end
