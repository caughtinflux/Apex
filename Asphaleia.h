#import <Foundation/Foundation.h>

@interface asphaleiaMainClass : NSObject
+ (instancetype)sharedInstance;
- (BOOL)possiblyProtectApp:(NSString *)appID inView:(SBIconView *)iconView;
@end
