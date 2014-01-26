#import "STKEmptyIcon.h"
#import "STKConstants.h"

%subclass STKEmptyIcon : SBIcon

- (id)getIconImage:(NSInteger)imgType
{
    return [[[UIImage alloc] init] autorelease];
}

- (BOOL)isEmptyPlaceholder
{
	return YES;
}

%end

