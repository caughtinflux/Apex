#import "STKGroupLayout.h"
#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>

NSString * const STKPositionTopKey = @"STKPositionTop";
NSString * const STKPositionBottomKey = @"STKPositionBottom";
NSString * const STKPositionLeftKey = @"STKPositionLeft";
NSString * const STKPositionRightKey = @"STKPositionRight";
NSString * const STKPositionUnknownKey = @"STKPositionUnknown";

NSString * NSStringFromLayoutPosition(STKLayoutPosition position)
{
    switch (position) {
        case STKPositionTop: {
            return STKPositionTopKey;
        }
        case STKPositionBottom: {
            return STKPositionBottomKey;
        }
        case STKPositionLeft: {
            return STKPositionLeftKey;
        }
        case STKPositionRight: {
            return STKPositionRightKey;
        }
        default: {
            return STKPositionUnknownKey;
        }
    }
}

static STKLayoutPosition _PositionFromString(NSString *string)
{
    if ([string isEqual:STKPositionTopKey]) return STKPositionTop;
    if ([string isEqual:STKPositionBottomKey]) return STKPositionBottom;
    if ([string isEqual:STKPositionLeftKey]) return STKPositionLeft;
    if ([string isEqual:STKPositionRightKey]) return STKPositionRight;
    
    return STKPositionUnknown;
}

#define KEY(_p) NSStringFromLayoutPosition(_p)
#define TONUM(_p) [NSNumber numberWithUnsignedInteger:_p]
#define ALL_KEYS @[STKPositionTopKey, STKPositionBottomKey, STKPositionLeftKey, STKPositionRightKey]

@implementation STKGroupLayout
{
    NSMutableArray *_topIcons, *_bottomIcons, *_leftIcons, *_rightIcons, *_unknownIcons;
}

+ (NSArray *)allPositions
{
    return @[TONUM(STKPositionTop), TONUM(STKPositionBottom), TONUM(STKPositionRight), TONUM(STKPositionLeft)];
}

// Init using dictionary of an array of identifiers for every layout position
- (instancetype)initWithIdentifierDictionary:(NSDictionary *)dictionary
{
    if ((self = [self init])) {
        for (NSString *key in ALL_KEYS) {
            STKLayoutPosition currentPosition = _PositionFromString(key);
            NSArray *iconIDs = dictionary[key];
            if (iconIDs.count != 0) {
                for (NSString *ID in iconIDs) {
                    SBIcon *icon = [[(SBIconController *)[CLASS(SBIconController) sharedInstance] model] expectedIconForDisplayIdentifier:ID];
                    [self addIcon:icon toIconsAtPosition:currentPosition];
                }
            }
            else {
                self[currentPosition] = @[];
            }
        }
    }
    return self;
}

// Init using dictionary of an array of icons for every layout position
- (instancetype)initWithIconDictionary:(NSDictionary *)dictionary
{
    if ((self = [self init])) {
        for (NSString *key in ALL_KEYS) {
            STKLayoutPosition currentPosition = _PositionFromString(key);
            NSArray *icons = dictionary[key];
            self[currentPosition] = (icons.count > 0) ? icons : @[];
        }
    }
    return self;
}

- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    if ((self = [super init])) {
        _topIcons = [topIcons mutableCopy];
        _bottomIcons = [bottomIcons mutableCopy];
        _leftIcons = [leftIcons mutableCopy];
        _rightIcons = [rightIcons mutableCopy];
    }
    return self;
}

+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    return [[[self alloc] initWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons] autorelease];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _topIcons = [NSMutableArray new];
        _bottomIcons = [NSMutableArray new];
        _leftIcons = [NSMutableArray new];
        _rightIcons = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [_topIcons release];
    [_bottomIcons release];
    [_leftIcons release];
    [_rightIcons release];

    [super dealloc];
}

- (NSDictionary *)identifierDictionary
{
    return @{
        STKPositionTopKey: [_topIcons valueForKey:@"leafIdentifier"] ?: @[],
        STKPositionBottomKey: [_bottomIcons valueForKey:@"leafIdentifier"] ?: @[],
        STKPositionLeftKey: [_leftIcons valueForKey:@"leafIdentifier"] ?: @[],
        STKPositionRightKey: [_rightIcons valueForKey:@"leafIdentifier"] ?: @[],
        STKPositionUnknownKey: [_unknownIcons valueForKey:@"leafIdentifier"] ?: @[]
    };
}

- (NSDictionary *)iconDictionary
{
    return @{
        STKPositionTopKey: _topIcons ?: @[],
        STKPositionBottomKey: _bottomIcons ?: @[],
        STKPositionLeftKey: _leftIcons ?: @[],
        STKPositionRightKey: _rightIcons ?: @[],
        STKPositionUnknownKey: _unknownIcons ?: @[]
    };
}

- (NSArray *)allIcons
{
    NSMutableArray *array = [NSMutableArray array];
    [array addObjectsFromArray:_topIcons];
    [array addObjectsFromArray:_bottomIcons];
    [array addObjectsFromArray:_leftIcons];
    [array addObjectsFromArray:_rightIcons];
    return array;
}

- (id)iconAtSlot:(STKGroupSlot)slot
{
    return self[slot.position][slot.index];
}

- (void)addIcons:(NSArray *)icons toIconsAtPosition:(STKLayoutPosition)position
{
    [self[position] addObjectsFromArray:icons];
}

- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position
{
    [self[position] addObject:icon];
}

- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position atIndex:(NSUInteger)idx
{
    NSParameterAssert(idx <= [self[position] count]);
    [self[position] insertObject:icon atIndex:idx];
}

- (void)removeIcon:(SBIcon *)icon fromIconsAtPosition:(STKLayoutPosition)position
{
    [self[position] removeObject:icon];
}

- (void)removeIcons:(NSArray *)icons fromIconsAtPosition:(STKLayoutPosition)position;
{
    [self[position] removeObjectsInArray:icons];
}

- (void)enumerateIconsUsingBlockWithIndexes:(void(^)(id icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL *stop))block
{
    for (STKLayoutPosition i = 1; i <= 4; i++) {
        NSArray *icons = self[i];
        [icons enumerateObjectsUsingBlock:^(id icon, NSUInteger idx, BOOL *stop) {
            block(icon, i, icons, idx, stop);
        }];
    }
}

// Use syntactic sugar to get the icons you need
// layout[STKLayoutPositionTop]
- (NSMutableArray *)objectAtIndexedSubscript:(STKLayoutPosition)position
{
    if (position < STKPositionTop || position > STKPositionRight) {
        return _unknownIcons;
    }
    NSMutableArray *icons[4] = {_topIcons, _bottomIcons, _leftIcons, _rightIcons};
    return icons[position - 1];
}

- (void)setObject:(NSArray *)obj atIndexedSubscript:(STKLayoutPosition)position
{
    position = (position >= STKPositionTop || position <= STKPositionRight) ? position : STKPositionUnknown;
    NSMutableArray **icons[5] = {&_unknownIcons, &_topIcons, &_bottomIcons, &_leftIcons, &_rightIcons};
    NSMutableArray **selected = NULL;
    selected = icons[position];
    [*selected release];
    *selected = [obj mutableCopy] ?: [[NSMutableArray alloc] init];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackBuf count:(NSUInteger)count
{
    return [[self allIcons] countByEnumeratingWithState:state objects:stackBuf count:count];
}

@end
