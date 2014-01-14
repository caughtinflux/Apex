#import "STKConstants.h"

@interface STKPreferences : NSObject

+ (instancetype)preferences;

- (void)addGroup:(STKGroup *)group;
- (void)removeGroup:(STKGroup *)group;

@end
