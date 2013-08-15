#import <Foundation/Foundation.h>

@class SBIcon;

#ifdef __cplusplus 
extern "C" {
#endif

    extern NSString * const STKTopIconsKey;
    extern NSString * const STKBottomIconsKey;
    extern NSString * const STKLeftIconsKey;
    extern NSString * const STKRightIconsKey;

#ifdef __cplusplus
}
#endif

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

// Returns an autoreleased instance
+ (instancetype)layoutWithDictionary:(NSDictionary *)dictionary;
+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
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

- (STKLayoutPosition)positionForIcon:(id)icon;

- (NSDictionary *)dictionaryRepresentation;


NSString * STKNSStringFromPosition(STKLayoutPosition pos);

@end
