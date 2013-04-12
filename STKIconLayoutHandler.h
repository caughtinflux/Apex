#import <Foundation/Foundation.h>
#import "STKConstants.h"

@class STKIconLayout;

@interface STKIconLayoutHandler : NSObject

- (STKIconLayout *)layoutForIcons:(NSArray *)icons;

@end
