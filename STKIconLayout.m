#import "STKIconLayout.h"
#import "STKConstants.h"

#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>

NSString * const STKTopIconsKey = @"TopIcons";
NSString * const STKBottomIconsKey = @"BottomIcons";
NSString * const STKLeftIconsKey = @"LeftIcons";
NSString * const STKRightIconsKey = @"RightIcons";

@implementation STKIconLayout
{
    NSMutableArray *_topIcons;
    NSMutableArray *_bottomIcons;
    NSMutableArray *_leftIcons;
    NSMutableArray *_rightIcons;

    NSArray             *_allIcons;
    NSMutableDictionary *_dictRepr;
    BOOL                 _hasBeenModified;
} 

// SublimeClang throws an errors on @(somePos). Really. Annoying
#define TO_NUMBER(_i) [NSNumber numberWithInteger:_i]
+ (NSArray *)allPositions
{
    return @[TO_NUMBER(STKLayoutPositionTop), TO_NUMBER(STKLayoutPositionBottom), TO_NUMBER(STKLayoutPositionLeft), TO_NUMBER(STKLayoutPositionRight)];
}

+ (instancetype)layoutWithDictionary:(NSDictionary *)dict
{
    return [[[self alloc] initWithDictionary:dict] autorelease];
}

+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    return [[[self alloc] initWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons] autorelease];
}

+ (instancetype)layoutWithLayout:(STKIconLayout *)layout
{
    return [[[self alloc] initWithLayout:layout] autorelease];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    NSMutableArray *topIcons = [NSMutableArray array];
    NSMutableArray *bottomIcons = [NSMutableArray array];
    NSMutableArray *leftIcons = [NSMutableArray array];
    NSMutableArray *rightIcons = [NSMutableArray array];

    SBIconModel *model = (SBIconModel *)[[objc_getClass("SBIconController") sharedInstance] model];
    
    MAP(dict[STKTopIconsKey], ^(NSString *ID) { 
        id icon = [model expectedIconForDisplayIdentifier:ID];
        if (icon) {
            [topIcons addObject:icon];
        }
    });

    MAP(dict[STKBottomIconsKey], ^(NSString *ID) { 
        id icon = [model expectedIconForDisplayIdentifier:ID];
        if (icon) {
            [bottomIcons addObject:icon];
        }
    });

    MAP(dict[STKLeftIconsKey], ^(NSString *ID) { 
        id icon = [model expectedIconForDisplayIdentifier:ID];
        if (icon) {
            [leftIcons addObject:icon];
        }
    });

    MAP(dict[STKRightIconsKey], ^(NSString *ID) { 
        id icon = [model expectedIconForDisplayIdentifier:ID];
        if (icon) {
            [rightIcons addObject:icon];
        }
    });

    return [self initWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons];
}

- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    if ((self = [super init])) {
        _topIcons    = [topIcons mutableCopy];
        _bottomIcons = [bottomIcons mutableCopy];
        _leftIcons   = [leftIcons mutableCopy];
        _rightIcons  = [rightIcons mutableCopy];
    }
    return self;
}

- (instancetype)initWithLayout:(STKIconLayout *)layout
{
    if ((self = [super init])) {
        _topIcons = [layout.topIcons copy];
        _bottomIcons = [layout.bottomIcons copy];
        _leftIcons = [layout.leftIcons copy];
        _rightIcons = [layout.rightIcons copy];
    }
    return self;
}

- (void)dealloc
{
    [_topIcons release];
    [_bottomIcons release];
    [_leftIcons release];
    [_rightIcons release];

    _topIcons    = nil;
    _bottomIcons = nil;
    _leftIcons   = nil;
    _rightIcons  = nil;

    [super dealloc];
}

- (void)enumerateIconsUsingBlock:(void(^)(id, STKLayoutPosition))block
{
    MAP([[self class] allPositions], ^(NSNumber *number) {
        MAP([self iconsForPosition:[number integerValue]], ^(SBIcon *icon) { 
            block(icon, [number integerValue]); 
        });
    });
}

- (void)enumerateIconsUsingBlockWithIndexes:(void(^)(id icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index))block
{
    __block STKIconLayout *wSelf = self;

    [self.topIcons enumerateObjectsUsingBlock:^(SBIcon *icon, NSUInteger idx, BOOL *stop) {
        block(icon, STKLayoutPositionTop, wSelf.topIcons, idx);
    }];

    [self.bottomIcons enumerateObjectsUsingBlock:^(SBIcon *icon, NSUInteger idx, BOOL *stop) {
        block(icon, STKLayoutPositionBottom, wSelf.bottomIcons, idx);
    }];

    [self.leftIcons enumerateObjectsUsingBlock:^(SBIcon *icon, NSUInteger idx, BOOL *stop) {
        block(icon, STKLayoutPositionLeft, wSelf.leftIcons, idx);
    }];

    [self.rightIcons enumerateObjectsUsingBlock:^(SBIcon *icon, NSUInteger idx, BOOL *stop) {
        block(icon, STKLayoutPositionRight, wSelf.rightIcons, idx);
    }];
}

- (NSArray *)iconsForPosition:(STKLayoutPosition)position
{
    return ((position == STKLayoutPositionTop) ? self.topIcons : (position == STKLayoutPositionBottom) ? self.bottomIcons : (position == STKLayoutPositionLeft) ? self.leftIcons : self.rightIcons);
}

- (NSArray *)allIcons
{
    if (!_hasBeenModified && _allIcons) {
        return _allIcons;
    }

    [_allIcons release];
    _allIcons = nil;

    _allIcons = [[NSMutableArray alloc] initWithCapacity:self.totalIconCount];
    
    [(NSMutableArray *)_allIcons addObjectsFromArray:self.topIcons];
    [(NSMutableArray *)_allIcons addObjectsFromArray:self.bottomIcons];
    [(NSMutableArray *)_allIcons addObjectsFromArray:self.leftIcons];
    [(NSMutableArray *)_allIcons addObjectsFromArray:self.rightIcons];

    return _allIcons;
}

- (NSUInteger)totalIconCount
{
    return (self.topIcons.count + self.bottomIcons.count + self.leftIcons.count + self.rightIcons.count);
}

- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position
{
    if (!icon || position < STKLayoutPositionTop || position > STKLayoutPositionRight) {
        return;
    }
    @synchronized(self) {
        NSMutableArray **array = NULL;
        switch (position) {
            case STKLayoutPositionTop: {
                if (!_topIcons)  _topIcons = [NSMutableArray new];
                array = &_topIcons;
                break;
            }

            case STKLayoutPositionBottom: {
                if (!_bottomIcons) _bottomIcons = [NSMutableArray new];
                array = &_bottomIcons;
                break;
            }

            case STKLayoutPositionLeft: {
                if (!_leftIcons) _leftIcons = [NSMutableArray new];
                array = &_leftIcons;
                break;
            }
            
            case STKLayoutPositionRight: {
                if (!_rightIcons) _rightIcons = [NSMutableArray new];
                array = &_rightIcons;
                break;
            }

            default: {

            }
        }

        _hasBeenModified = YES;
        [*array addObject:icon];
    }
}

- (void)setIcon:(id)icon atIndex:(NSUInteger)idx position:(STKLayoutPosition)position
{
    if (!icon || position < STKLayoutPositionTop || position > STKLayoutPositionRight) {
        return;
    }
    @synchronized(self) {
        NSMutableArray *icons = (NSMutableArray *)[self iconsForPosition:position];
        if (idx < icons.count){
            [icons removeObjectAtIndex:idx];
            [icons insertObject:icon atIndex:idx];
        }
        else {
            [icons addObject:icon];
        }
       _hasBeenModified = YES;
    }
}

- (void)removeIcon:(id)icon fromIconsAtPosition:(STKLayoutPosition)position
{
    if (!icon || position < STKLayoutPositionTop || position > STKLayoutPositionRight) {
        return;
    }
    @synchronized(self) {
        NSMutableArray *array = (NSMutableArray *)[self iconsForPosition:position];
        [array removeObject:icon];
        _hasBeenModified = YES;
    }
}

- (void)removeIcon:(id)icon
{
    if (!icon) {
        return;
    }

    @synchronized(self) {
        [_topIcons removeObject:icon];
        [_bottomIcons removeObject:icon];
        [_leftIcons removeObject:icon];
        [_rightIcons removeObject:icon];

        _hasBeenModified = YES;
    }
}

- (void)removeAllIconsFromPosition:(STKLayoutPosition)position
{
    @synchronized(self) {
        [(NSMutableArray *)[self iconsForPosition:position] removeAllObjects];
        _hasBeenModified = YES;
    }
}

- (void)removeAllIcons
{
    @synchronized(self) {
        for (NSNumber *position in [[self class] allPositions])
            [(NSMutableArray *)[self iconsForPosition:[position integerValue]] removeAllObjects];   

        _hasBeenModified = YES;
    }
}

- (void)removeIconAtIndex:(NSUInteger)idx fromIconsAtPosition:(STKLayoutPosition)position;
{
    @synchronized(self) {
        NSMutableArray *array = (NSMutableArray *)[self iconsForPosition:position];
        if (array.count > 0 && idx < array.count) {
            [array removeObjectAtIndex:idx];
        }
        else {
            NSLog(@"[%@] %s: Index %i is out of bounds of array at position: %i. Dying silently", kSTKTweakName, __PRETTY_FUNCTION__, idx, position);
        }
        _hasBeenModified = YES;
    }
}

- (STKLayoutPosition)positionForIcon:(id)icon
{
    if ([_topIcons containsObject:icon]) return STKLayoutPositionTop;
    if ([_bottomIcons containsObject:icon]) return STKLayoutPositionBottom;
    if ([_leftIcons containsObject:icon]) return STKLayoutPositionLeft;
    if ([_rightIcons containsObject:icon]) return STKLayoutPositionRight;

    return NSNotFound;
}

- (void)getPosition:(STKLayoutPosition *)positionRef andIndex:(NSUInteger *)idxRef forIcon:(id)icon
{
    STKLayoutPosition pos = [self positionForIcon:icon];
    if (positionRef) {
        *positionRef = pos;
    }
    
    NSUInteger idx = [[self iconsForPosition:pos] indexOfObject:icon];
    if (idxRef) {
        *idxRef = idx;
    }
}

- (NSDictionary *)dictionaryRepresentation
{
    if (_dictRepr && !_hasBeenModified) {
        return _dictRepr;
    }

    [_dictRepr release];
    _dictRepr = nil;
    _dictRepr = [[NSMutableDictionary alloc] initWithCapacity:4];

    if (_topIcons) {
        _dictRepr[STKTopIconsKey] = [_topIcons valueForKey:@"leafIdentifier"];
    }
    if (_bottomIcons) {
        _dictRepr[STKBottomIconsKey] = [_bottomIcons valueForKey:@"leafIdentifier"];
    }
    if (_leftIcons) {
        _dictRepr[STKLeftIconsKey] = [_leftIcons valueForKey:@"leafIdentifier"];
    }
    if (_rightIcons) {
        _dictRepr[STKRightIconsKey] = [_rightIcons valueForKey:@"leafIdentifier"];
    }

    return _dictRepr;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ top.count: %i bottom.count: %i left.count: %i right.count: %i", [super description], _topIcons.count, _bottomIcons.count, _leftIcons.count, _rightIcons.count];
}

NSString * STKNSStringFromPosition(STKLayoutPosition pos)
{
    switch (pos) {
        case STKLayoutPositionTop:
            return @"STKLayoutPositionTop";
        case STKLayoutPositionBottom:
            return @"STKLayoutPositionBottom";
        case STKLayoutPositionLeft:
            return @"STKLayoutPositionLeft";
        case STKLayoutPositionRight:
            return @"STKLayoutPositionRight";
        default:
            return @"STKLayoutPositionNone";
    }
}

@end
