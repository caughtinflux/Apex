#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, STKLayoutPosition) {
	STKPositionUnknown = -1,
	STKPositionTop 	   = 1,
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

- (NSDictionary *)identifierDictionary;
- (NSDictionary *)iconDictionary;

// Use syntactic sugar to get the icons you need
// layout[STKLayoutPositionTop]
- (id)objectAtIndexedSubscript:(STKLayoutPosition)position;
- (void)setObject:(id)icons atIndexedSubscript:(STKLayoutPosition)position;

- (void)addIcons:(NSArray *)icons toIconsAtPosition:(STKLayoutPosition)position;
- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position;
- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position atIndex:(NSUInteger)idx;

@end
