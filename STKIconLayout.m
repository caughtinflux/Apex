#import "STKIconLayout.h"
#import "STKConstants.h"

@implementation STKIconLayout 

+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    return [[[self alloc] initWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons] autorelease];
}

- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    if ((self = [super init])) {
        _topIcons    = [topIcons copy];
        _bottomIcons = [bottomIcons copy];
        _leftIcons   = [leftIcons copy];
        _rightIcons  = [rightIcons copy];
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

+ (NSArray *)allPositions
{
    return @[@(STKLayoutPositionTop), @(STKLayoutPositionBottom), @(STKLayoutPositionLeft), @(STKLayoutPositionRight)];
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
    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:self.totalIconCount];
    
    [ret addObjectsFromArray:self.topIcons];
    [ret addObjectsFromArray:self.bottomIcons];
    [ret addObjectsFromArray:self.leftIcons];
    [ret addObjectsFromArray:self.rightIcons];

    return ret;
}

- (NSUInteger)totalIconCount
{
    return (self.topIcons.count + self.bottomIcons.count + self.leftIcons.count + self.rightIcons.count);
}

- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position
{
    if (!icon) {
        return;
    }
    @synchronized(self) {
        switch (position) {
            case STKLayoutPositionTop: {
                NSMutableArray *newTopIcons = [_topIcons mutableCopy];
                if (!newTopIcons) {
                    newTopIcons = [NSMutableArray new];
                }
                [newTopIcons addObject:icon];
                
                [_topIcons release];
                _topIcons = [newTopIcons copy]; // We don't want a mutable array as an ivar
                [newTopIcons release];
                break;
            }

            case STKLayoutPositionBottom: {
                NSMutableArray *newBottomIcons = [_bottomIcons mutableCopy];
                if (!newBottomIcons) {
                    newBottomIcons = [NSMutableArray new];
                }
                [newBottomIcons addObject:icon];

                [_bottomIcons release];
                _bottomIcons = [newBottomIcons copy];
                [newBottomIcons release];
                break;
            }

            case STKLayoutPositionLeft: {
                NSMutableArray *newLeftIcons = [_leftIcons mutableCopy];
                if (!newLeftIcons) {
                    newLeftIcons = [NSMutableArray new];
                }
                [newLeftIcons addObject:icon];

                [_leftIcons release];
                _leftIcons = [newLeftIcons copy];
                [newLeftIcons release];
                break;
            }
            
            case STKLayoutPositionRight: {
                NSMutableArray *newRightIcons = [_rightIcons mutableCopy];
                if (!newRightIcons) {
                    newRightIcons = [NSMutableArray new];
                }
                [newRightIcons addObject:icon];

                [_rightIcons release];
                _rightIcons = [newRightIcons copy];
                [newRightIcons release];
                break;
            }
        }
    }
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
