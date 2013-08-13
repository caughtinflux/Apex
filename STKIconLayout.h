#import <Foundation/Foundation.h>

@class SBIcon;

@interface STKIconLayout : NSObject

@property(nonatomic, readonly) NSArray *topIcons;
@property(nonatomic, readonly) NSArray *bottomIcons;
@property(nonatomic, readonly) NSArray *leftIcons;
@property(nonatomic, readonly) NSArray *rightIcons;

typedef NS_ENUM(NSInteger, STKLayoutPosition) {
	STKLayoutPositionTop = 1,
	STKLayoutPositionBottom,
	STKLayoutPositionLeft,
	STKLayoutPositionRight,
};

// All these arrays contain SBIcon objects
// Returns an autoreleased instance
+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;
- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;

+ (NSArray *)allPositions;

@property (nonatomic, assign) BOOL containsPlaceholders;

- (void)enumerateThroughAllIconsUsingBlock:(void(^)(id, STKLayoutPosition))block;
- (void)enumerateIconsUsingBlockWithIndexes:(void(^)(id icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index))block;

// Methods to query all the things
- (NSArray *)iconsForPosition:(STKLayoutPosition)position;
- (NSArray *)allIcons;
- (NSUInteger)totalIconCount;

// This method is thread safe
- (void)addIcon:(id)icon toIconsAtPosition:(STKLayoutPosition)position;


NSString * STKNSStringFromPosition(STKLayoutPosition pos);

@end
