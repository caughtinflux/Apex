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

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ top.count: %i bottom.count: %i left.count: %i right.count: %i", [super description], _topIcons.count, _bottomIcons.count, _leftIcons.count, _rightIcons.count];
}

@end
