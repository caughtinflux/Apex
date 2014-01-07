#import <SpringBoard/SpringBoard.h>
#import "STKConstants.h"

static NSString * STKApexEnabledFolder = @"STKApexEnabledFolder";
//static NSString * STKApexCentralIcon = @"STKApexCentralIcon";

%hook SBFolder

- (NSDictionary *)representation
{
    NSMutableDictionary *repr = [%orig() mutableCopy];
    repr[STKApexEnabledFolder] = @([self isApexFolder]);
    //repr[STKApexCentralIcon] = [[self centralIconForApex] leafIdentifier];
    return [repr autorelease];
}

%new
- (void)convertToApexFolder
{
    objc_setAssociatedObject(self, @selector(isApexFolder), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)convertToRegularFolder
{
    objc_setAssociatedObject(self, @selector(isApexFolder), @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (BOOL)isApexFolder
{
    return [objc_getAssociatedObject(self, @selector(isApexFolder)) boolValue];
}

%new
- (SBIcon *)centralIconForApex
{
    return [self iconAtIndexPath:[NSIndexPath indexPathWithIconIndex:0 listIndex:0]];
}

%end
