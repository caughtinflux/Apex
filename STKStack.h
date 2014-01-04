#import <Foundation/Foundation.h>

@class SBIcon, STKGroupLayout;
@interface STKGroup : NSObject

+ (instancetype)emptyGroupWithCentralIcon:(SBIcon *)icon;
+ (instancetype)groupWithCentralIcon:(SBIcon *)icon layout:(STKGroupLayout *)layout;

@end
