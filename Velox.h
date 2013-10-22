#import <Foundation/Foundation.h>
@interface Velox : NSObject
+ (instancetype)sharedManager;
- (int)intForPreferenceKey:(NSString *)key;
@end
