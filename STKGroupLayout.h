#import <Foundation/Foundation.h>
#import "STKConstants.h"

extern NSString * const STKPositionTopKey;
extern NSString * const STKPositionBottomKey;
extern NSString * const STKPositionLeftKey;
extern NSString * const STKPositionRightKey;
extern NSString * const STKPositionUnknownKey;

extern NSString * NSStringFromLayoutPosition(STKLayoutPosition position);

#define STKPositionIsVertical(_pos) (_pos == STKPositionTop || _pos == STKPositionBottom)
#define STKPositionIsHorizontal(_pos) (_pos == STKPositionLeft || _pos == STKPositionRight)

@class SBIcon;
@interface STKGroupLayout : NSObject <NSFastEnumeration>

// Init using dictionary of an array of identifiers for every layout position.
- (instancetype)initWithIdentifierDictionary:(NSDictionary *)dictionary;
// Init using dictionary of an array of icons for every layout position
- (instancetype)initWithIconDictionary:(NSDictionary *)dictionary;

- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;
+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons;

- (NSDictionary *)identifierDictionary;
- (NSDictionary *)iconDictionary;

@property (nonatomic, readonly) NSArray *topIcons;
@property (nonatomic, readonly) NSArray *bottomIcons;
@property (nonatomic, readonly) NSArray *leftIcons;
@property (nonatomic, readonly) NSArray *rightIcons;

- (NSArray *)allIcons;

// Use syntactic sugar to get the icons you need
// layout[STKLayoutPositionTop]
- (id)objectAtIndexedSubscript:(STKLayoutPosition)position;
- (void)setObject:(id)icons atIndexedSubscript:(STKLayoutPosition)position;

- (id)iconInSlot:(STKGroupSlot)slot;
- (void)setIcon:(id)icon inSlot:(STKGroupSlot)slot;
- (STKGroupSlot)slotForIcon:(id)icon;

- (void)addIcons:(NSArray *)icons toIconsAtPosition:(STKLayoutPosition)position;
- (void)addIcon:(id)icon toIconsAtPosition:(STKLayoutPosition)position;
- (void)addIcon:(id)icon toIconsAtPosition:(STKLayoutPosition)position atIndex:(NSUInteger)idx;

- (void)removeIcon:(id)icon fromIconsAtPosition:(STKLayoutPosition)position;
- (void)removeIcons:(NSArray *)icons fromIconsAtPosition:(STKLayoutPosition)position;

- (BOOL)containsIcon:(id)icon;

- (void)enumerateIconsUsingBlockWithIndexes:(void(^)(id icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL *stop))block;

@end
