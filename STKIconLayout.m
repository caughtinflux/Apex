#import "STKIconLayout.h"
#import "STKConstants.h"


@implementation STKIconLayout
{
    NSMutableArray *_topIcons;
    NSMutableArray *_bottomIcons;
    NSMutableArray *_leftIcons;
    NSMutableArray *_rightIcons;

    NSArray        *_allIcons;
    BOOL            _hasBeenModified;
} 

+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    return [[[self alloc] initWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons] autorelease];
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

// SublimeClang throws an errors on @(somePos). Really. Annoying
#define TO_NUMBER(_i) [NSNumber numberWithInteger:_i]
+ (NSArray *)allPositions
{
    return @[TO_NUMBER(STKLayoutPositionTop), TO_NUMBER(STKLayoutPositionBottom), TO_NUMBER(STKLayoutPositionLeft), TO_NUMBER(STKLayoutPositionRight)];
}

- (void)enumerateThroughAllIconsUsingBlock:(void(^)(id, STKLayoutPosition))block
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
    if (!_hasBeenModified && !_allIcons) {
        return _allIcons;
    }

    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:self.totalIconCount];
    
    [ret addObjectsFromArray:self.topIcons];
    [ret addObjectsFromArray:self.bottomIcons];
    [ret addObjectsFromArray:self.leftIcons];
    [ret addObjectsFromArray:self.rightIcons];

    _allIcons = [ret retain];

    return ret;
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
        }

        _hasBeenModified = YES;
        [*array addObject:icon];
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
    }
}

@end
