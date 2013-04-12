#import <Foundation/Foundation.h>

@interface STKIconLayout : NSObject

@property(nonatomic, readonly) NSArray *topIcons;
@property(nonatomic, readonly) NSArray *bottomIcons;
@property(nonatomic, readonly) NSArray *leftIcons;
@property(nonatomic, readonly) NSArray *rightIcons;

// All these arrays contain SBIcon objects
// Returns an autoreleased instance
+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;
- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;

@end
