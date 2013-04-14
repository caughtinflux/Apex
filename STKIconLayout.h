#import <Foundation/Foundation.h>

@class SBIcon;

@interface STKIconLayout : NSObject

@property(nonatomic, readonly) NSArray *topIcons;
@property(nonatomic, readonly) NSArray *bottomIcons;
@property(nonatomic, readonly) NSArray *leftIcons;
@property(nonatomic, readonly) NSArray *rightIcons;

typedef enum {
	STKLayoutPositionTop = 1,
	STKLayoutPositionBottom,
	STKLayoutPositionLeft,
	STKLayoutPositionRight,
} STKLayoutPosition;

// All these arrays contain SBIcon objects
// Returns an autoreleased instance
+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;

- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;

- (void)enumerateThroughAllIconsUsingBlock:(void(^)(SBIcon *, STKLayoutPosition))block;

@end
