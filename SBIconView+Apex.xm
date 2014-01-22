#import "SBIconView+Apex.h"
#import "STKConstants.h"

%hook SBIconView

%new
- (void)setGroupView:(STKGroupView *)groupView
{
    [self removeGroupView];
    objc_setAssociatedObject(self, @selector(STKGroupView), groupView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addSubview:groupView];
    [self sendSubviewToBack:groupView];
}

%new 
- (void)removeGroupView
{
    STKGroupView *view = [self groupView];
    [view resetLayouts];
    [view removeFromSuperview];
    objc_setAssociatedObject(self, @selector(STKGroupView), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (STKGroupView *)groupView
{
    return objc_getAssociatedObject(self, @selector(STKGroupView));
}

- (void)setAlpha:(CGFloat)alpha
{
    %orig(alpha);

    CGFloat prevMax = 1.0f;
    CGFloat prevMin = 0.2;
    CGFloat newMax = 1.0f;
    CGFloat newMin = 0.0f;

    CGFloat oldRange = (prevMax - prevMin);
    CGFloat newRange = (newMax - newMin);

    CGFloat groupAlpha = (((alpha - prevMin) * newRange) / oldRange) + newMin;

    [[self groupView] setAlpha:groupAlpha];
}

%end
