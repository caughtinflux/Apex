#import <SpringBoard/SBIconViewMap.h>

@class SBIcon, SBIconView;
@interface SBIconViewMap (STKSafety)
- (SBIconView *)safeIconViewForIcon:(SBIcon *)icon;
@end
