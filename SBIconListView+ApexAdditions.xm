#import <SpringBoard/SpringBoard.h>
#import <dlfcn.h>
#import "SBIconListView+ApexAdditions.h"

%hook SBIconListView
static CGFloat _verticalPadding = -1337.f;
static CGFloat _horizontalPadding = -1337.f;
static BOOL _hasGridlock;

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
    if (_verticalPadding == -1337.f) {
        CGFloat defaultIconHeight = [%c(SBIconView) defaultIconSize].height;
        CGFloat position1 = [self originForIconAtX:0 Y:0].y;
        CGFloat position2 = [self originForIconAtX:0 Y:1].y;
        _verticalPadding = (position2 - position1 - defaultIconHeight);
    }
    return _verticalPadding;
}

%new
- (CGFloat)stk_realHorizontalIconPadding
{
    if (_horizontalPadding == -1337.f) {
        CGFloat defaultIconWidth = [%c(SBIconView) defaultIconSize].width;
        CGFloat position1 = 0.f;
        CGFloat position2 = 0.f;
        if (([self visibleIcons].count >= 2) && _hasGridlock == NO) {
            position1 = [[self viewMap] mappedIconViewForIcon:[self visibleIcons][0]].frame.origin.x;
            position2 = [[self viewMap] mappedIconViewForIcon:[self visibleIcons][1]].frame.origin.x;
        }
        else {
            position1 = [self originForIconAtX:0 Y:0].x;
            position2 = [self originForIconAtX:1 Y:0].x;
        }
        _horizontalPadding = (position2 - position1 - defaultIconWidth);
    }
    return _horizontalPadding;
}

- (void)layoutIconsNow
{
    _verticalPadding = -1337.f;
    _horizontalPadding = -1337.f;
    %orig();
}

%end

%ctor
{
    @autoreleasepool {
        %init();
        void *handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Gridlock.dylib", RTLD_NOW);
        _hasGridlock = !!handle;
    }   
}
