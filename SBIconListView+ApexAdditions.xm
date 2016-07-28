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

%new
- (void)setStk_modifyDisplacedIconOrigin:(BOOL)modify
{
    objc_setAssociatedObject(self, @selector(stk_modifyDisplacedIconOrigin), @(modify), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (BOOL)stk_modifyDisplacedIconOrigin
{
    return [objc_getAssociatedObject(self, @selector(stk_modifyDisplacedIconOrigin)) boolValue];
}

%new
- (void)setStk_preventRelayout:(BOOL)prevent
{
    objc_setAssociatedObject(self, @selector(stk_preventRelayout), @(prevent), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (BOOL)stk_preventRelayout
{
    return [objc_getAssociatedObject(self, @selector(stk_preventRelayout)) boolValue];
}

%new
- (void)stk_makeIconViewsPerformBlock:(void(^)(SBIconView *iv))block
{
    [self enumerateIconViewsUsingBlock:block];
}

%new
- (void)stk_reorderIconViews
{
    NSMutableArray *iconViews = [self.subviews mutableCopy];
    [iconViews sortUsingComparator:^NSComparisonResult(UIView *view1, UIView *view2) {
        if(fabs(view1.frame.origin.y - view2.frame.origin.y) > 0.01)
            return [@(view1.frame.origin.y) compare:@(view2.frame.origin.y)];
        else
            return [@(view1.frame.origin.x) compare:@(view2.frame.origin.x)];
    }];
    for (UIView *view in iconViews) {
        [view.superview bringSubviewToFront:view];
    }
}

- (void)prepareToRotateToInterfaceOrientation:(UIInterfaceOrientation)orient
{
    self.stk_realVerticalIconPadding = kInvalidIconPadding;
    self.stk_realHorizontalIconPadding = kInvalidIconPadding;
    %orig(orient);
}

- (CGPoint)originForIconAtCoordinate:(SBIconCoordinate)coordinate
{
    if (self.stk_modifyDisplacedIconOrigin) {
        SBIcon *icon = [[self model] iconAtIndex:[self indexForCoordinate:coordinate forOrientation:[UIApplication sharedApplication].statusBarOrientation]];
        STKGroupController *controller = [STKGroupController sharedController];
        STKGroupView *groupView = controller.openGroupView ?: controller.openingGroupView;
        if (!groupView.isAnimating && [[groupView.displacedIconLayout allIcons] containsObject:icon]) {
            return [self viewForIcon:icon].frame.origin;
        }
    }
    return %orig(coordinate);
}

- (void)layoutIconsNow
{
    if (self.stk_preventRelayout) {
        return;
    }
    self.stk_realHorizontalIconPadding = kInvalidIconPadding;
    self.stk_realHorizontalIconPadding = kInvalidIconPadding;
    %orig();
}

- (SBIcon *)layoutIconsIfNeeded:(NSTimeInterval)duration domino:(BOOL)domino
{
    if (self.stk_preventRelayout) {
        return nil;
    }
    return %orig();
}

- (void)setIconsNeedLayout
{
    if (self.stk_preventRelayout) {
        return;
    }
    %orig();
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
