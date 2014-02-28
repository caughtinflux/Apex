#import <SpringBoard/SpringBoard.h>
#import <dlfcn.h>
#import "STKConstants.h"
#import "SBIconListView+ApexAdditions.h"

#define kInvalidIconPadding -1337.f

static BOOL _hasGridlock;

%hook SBIconListView
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
- (void)setStk_realVerticalIconPadding:(CGFloat)padding
{
    objc_setAssociatedObject(self, @selector(stk_realVerticalIconPadding), @(padding), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (CGFloat)stk_realVerticalIconPadding
{
    CGFloat padding = [objc_getAssociatedObject(self, @selector(stk_realVerticalIconPadding)) floatValue];
    if (padding == kInvalidIconPadding || padding == 0.f) {
        if ([self isKindOfClass:CLASS(SBDockIconListView)]) {
            padding = [[CLASS(SBIconController) sharedInstance] currentRootIconList].stk_realVerticalIconPadding;
        }
        else {
            CGFloat defaultIconHeight = [%c(SBIconView) defaultIconSize].height;
            CGFloat position1 = [self originForIconAtCoordinate:(SBIconCoordinate){1, 1}].y;
            CGFloat position2 = [self originForIconAtCoordinate:(SBIconCoordinate){2, 1}].y;
            padding = (position2 - position1 - defaultIconHeight);
        }
        self.stk_realVerticalIconPadding = padding;
    }
    return padding;
}

%new
- (void)setStk_realHorizontalIconPadding:(CGFloat)padding
{
    objc_setAssociatedObject(self, @selector(stk_realHorizontalIconPadding), @(padding), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (CGFloat)stk_realHorizontalIconPadding
{
    CGFloat padding = [objc_getAssociatedObject(self, @selector(stk_realHorizontalIconPadding)) floatValue];
    if (padding == kInvalidIconPadding || padding == 0.f) {
        CGFloat defaultIconWidth = [%c(SBIconView) defaultIconSize].width;
        CGFloat position1 = 0.f;
        CGFloat position2 = 0.f;
        if (([self visibleIcons].count >= 2) && _hasGridlock == NO) {
            position1 = [[self viewMap] mappedIconViewForIcon:[self visibleIcons][0]].frame.origin.x;
            position2 = [[self viewMap] mappedIconViewForIcon:[self visibleIcons][1]].frame.origin.x;
        }
        else {
            position1 = [self originForIconAtCoordinate:(SBIconCoordinate){1, 1}].x;
            position2 = [self originForIconAtCoordinate:(SBIconCoordinate){1, 2}].x;
        }
        padding = (position2 - position1 - defaultIconWidth);
        self.stk_realHorizontalIconPadding = padding;
    }
    return padding;
}

- (void)layoutIconsNow
{
    self.stk_realHorizontalIconPadding = kInvalidIconPadding;
    self.stk_realHorizontalIconPadding = kInvalidIconPadding;
    %orig();
}

%new
- (void)stk_makeIconViewsPerformBlock:(void(^)(SBIconView *iv))block
{
    [self enumerateIconViewsUsingBlock:block];
}

%end

%ctor
{
    @autoreleasepool {
        %init();
        void *handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Gridlock.dylib", RTLD_NOW);
        _hasGridlock = (handle != nil);
    }   
}
