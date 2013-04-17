#import "STKIconLayout.h"

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

- (void)enumerateThroughAllIconsUsingBlock:(void(^)(SBIcon *, STKLayoutPosition))block
{
    [block copy];

    for (SBIcon *icon in self.topIcons) {
        block(icon, STKLayoutPositionTop);
    }
    for (SBIcon *icon in self.bottomIcons) {
        block(icon, STKLayoutPositionBottom);
    }
    for (SBIcon *icon in self.leftIcons) {
        block(icon, STKLayoutPositionLeft);
    }
    for (SBIcon *icon in self.rightIcons) {
        block(icon, STKLayoutPositionRight);
    }

    [block release];
}

- (void)enumerateIconsUsingBlockWithIndexes:(void(^)(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index))block
{
    STKIconLayout __block *wSelf = self;
    [block copy];

    [self.topIcons enumerateObjectsUsingBlock:^(SBIcon *icon, NSUInteger idx, BOOL *stop) {
        block(icon, STKLayoutPositionTop, wSelf.topIcons, idx);
    }];

    [self.bottomIcons enumerateObjectsUsingBlock:^(SBIcon *icon, NSUInteger idx, BOOL *stop) {
        block(icon, STKLayoutPositionBottom, wSelf.topIcons, idx);
    }];

    [self.leftIcons enumerateObjectsUsingBlock:^(SBIcon *icon, NSUInteger idx, BOOL *stop) {
        block(icon, STKLayoutPositionLeft, wSelf.topIcons, idx);
    }];

    [self.rightIcons enumerateObjectsUsingBlock:^(SBIcon *icon, NSUInteger idx, BOOL *stop) {
        block(icon, STKLayoutPositionRight, wSelf.topIcons, idx);
    }];

    [block release];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ top.count: %i bottom.count: %i left.count: %i right.count: %i", [super description], _topIcons.count, _bottomIcons.count, _leftIcons.count, _rightIcons.count];
}

@end
