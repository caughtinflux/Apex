#import "SBIconListView+ApexAdditions.h"

%hook SBIconListView

%new
- (NSUInteger)stk_visibleIconRowsForCurrentOrientation
{
	return ([self rowForIcon:[[self icons] lastObject]] + 1);
}

%new
- (NSUInteger)stk_visibleIconColumnsForCurrentOrientation
{
	return MIN([self icons].count, [self iconColumnsForCurrentOrientation]);
}
%end

%ctor
{
	@autoreleasepool {
		%init();
	}	
}
