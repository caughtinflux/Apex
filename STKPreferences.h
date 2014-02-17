#import "STKConstants.h"

@class STKGroup;
@interface STKPreferences : NSObject <STKGroupObserver>

+ (instancetype)sharedPreferences;

- (void)addOrUpdateGroup:(STKGroup *)group;
- (void)removeGroup:(STKGroup *)group;

- (STKGroup *)groupForIcon:(SBIcon *)icon;

@end
