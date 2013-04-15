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
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ top.count: %i bottom.count: %i left.count: %i right.count: %i", [super description], _topIcons.count, _bottomIcons.count, _leftIcons.count, _rightIcons.count];
}

@end
