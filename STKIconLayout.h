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

@interface STKIconLayout : NSObject <NSFastEnumeration>

typedef NS_ENUM(NSInteger, STKLayoutPosition) {
    STKLayoutPositionNone = 0,
    STKLayoutPositionTop,
    STKLayoutPositionBottom,
    STKLayoutPositionLeft,
    STKLayoutPositionRight,
};

#define STKLayoutPositionIsVertical(_position) (_position == STKLayoutPositionTop || _position == STKLayoutPositionBottom)
#define STKLayoutPositionIsHorizontal(_position) (_position == STKLayoutPositionLeft || _position == STKLayoutPositionRight)

// Returns an autoreleased instance
+ (instancetype)layoutWithDictionary:(NSDictionary *)dictionary;
+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;
+ (instancetype)layoutWithLayout:(STKIconLayout *)layout;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;
- (instancetype)initWithLayout:(STKIconLayout *)layout;

+ (NSArray *)allPositions;

@property (nonatomic, readonly) NSArray *topIcons;
@property (nonatomic, readonly) NSArray *bottomIcons;
@property (nonatomic, readonly) NSArray *leftIcons;
@property (nonatomic, readonly) NSArray *rightIcons;
@property (nonatomic, assign) BOOL containsPlaceholders;

- (void)enumerateIconsUsingBlock:(void(^)(id, STKLayoutPosition))block;
- (void)enumerateIconsUsingBlockWithIndexes:(void(^)(id icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index))block;

- (NSArray *)iconsForPosition:(STKLayoutPosition)position;
- (NSArray *)allIcons;
- (NSUInteger)totalIconCount;


- (void)addIcon:(id)icon toIconsAtPosition:(STKLayoutPosition)position;

/**
*   @param icon The icon to set at idx
*   @see idx
*   @param idx The index at which icon is to be set
*   @see icon
*   @param The STKLayoutPosition at which the icon is to be set
*
*   This method replaces the curr_icon at STKLayoutPosition position with index idx with icon, only if idx is less than the number of icons currently in that position. If the index is greater,
*   the icon is simply added to the icons at that position
*   @see icon
*   @see idx
*   @see position
*   
*/
- (void)setIcon:(id)icon atIndex:(NSUInteger)idx position:(STKLayoutPosition)position;

- (void)removeIcon:(id)icon fromIconsAtPosition:(STKLayoutPosition)position;
- (void)removeIcon:(id)icon; // Removes `icon` from all positions it can be found in
- (void)removeAllIconsForPosition:(STKLayoutPosition)position;
- (void)removeAllIcons;
- (void)removeIconAtIndex:(NSUInteger)idx fromIconsAtPosition:(STKLayoutPosition)position;


/**
*   @param icon The icon for which the position is to be found
*   @return The first position where icon is found
*   @see icon
*/
- (STKLayoutPosition)positionForIcon:(id)icon;
- (void)getPosition:(STKLayoutPosition *)positionRef andIndex:(NSUInteger *)idxRef forIcon:(id)icon;


- (NSDictionary *)dictionaryRepresentation;


NSString * STKNSStringFromPosition(STKLayoutPosition pos);

@end
