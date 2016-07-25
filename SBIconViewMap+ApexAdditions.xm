#import "SBIconViewMap+ApexAdditions.h"
#import "STKConstants.h"

%hook SBIconViewMap
%new
+ (instancetype)stk_homescreenMap {
    static dispatch_once_t pred;
    static BOOL respondsToOld;
    dispatch_once(&pred, ^{
        respondsToOld = [%c(SBIconViewMap) respondsToSelector:@selector(homescreenMap)];
    });
    if (respondsToOld) {
        return [%c(SBIconViewMap) homescreenMap];
    }
    else {
        return [[%c(SBIconController) sharedInstance] homescreenIconViewMap];
    }
}
%end