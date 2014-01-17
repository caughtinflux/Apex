#import "STKConstants.h"

@class STKGroup;
@interface STKPreferences : NSObject

+ (instancetype)preferences;

- (void)addOrUpdateGroup:(STKGroup *)group;
- (void)removeGroup:(STKGroup *)group;

- (STKGroup *)groupForIcon:(SBIcon *)icon;

@end
