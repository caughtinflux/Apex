#import <SpringBoard/SpringBoard.h>
#import "SBIconListView+ApexAdditions.h"

%hook SBIconListView
static CGFloat _padding = -1337.f;

%new
- (NSUInteger)stk_visibleIconRowsForCurrentOrientation
{
	return ([self rowForIcon:[[self icons] lastObject]] + 1);
}

%new
- (NSUInteger)stk_visibleIconColumnsForCurrentOrientation
{
	return MIN([self icons].count, [self iconColumnsForCurrentOrientation]);
}

%new
- (CGFloat)stk_realVerticalIconPadding
{
	if (_padding == -1337.f) {
		CGFloat defaultIconHeight = [%c(SBIconView) defaultIconSize].height;
		CGFloat position1 = [self originForIconAtX:0 Y:0].y;
		CGFloat position2 = [self originForIconAtX:0 Y:1].y;
		_padding = (position2 - position1 - defaultIconHeight);
	}
	return _padding;
}

- (void)layoutIconsNow
{
	_padding = -1337.f;
	%orig();
}

%end

%ctor
{
	@autoreleasepool {
		%init();
	}	
}
