#import <Foundation/Foundation.h>

extern NSString * const STKPositionTopKey;
extern NSString * const STKPositionBottomKey;
extern NSString * const STKPositionLeftKey;
extern NSString * const STKPositionRightKey;
extern NSString * const STKPositionUnknownKey;

typedef NS_ENUM(NSUInteger, STKLayoutPosition) {
    STKPositionUnknown = 0,
    STKPositionTop     = 1,
    STKPositionBottom  = 2,
    STKPositionLeft    = 3,
    STKPositionRight   = 4
};

extern NSString * NSStringFromLayoutPosition(STKLayoutPosition position);

@class SBIcon;
@interface STKGroupLayout : NSObject <NSFastEnumeration>

+ (NSArray *)allPositions;

// Init using dictionary of an array of identifiers for every layout position
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

- (void)addIcons:(NSArray *)icons toIconsAtPosition:(STKLayoutPosition)position;
- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position;
- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position atIndex:(NSUInteger)idx;

- (void)removeIcon:(SBIcon *)icon fromIconsAtPosition:(STKLayoutPosition)position;
- (void)removeIcons:(NSArray *)icons fromIconsAtPosition:(STKLayoutPosition)position;

@end
