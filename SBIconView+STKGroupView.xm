#import "SBIconView+STKGroupView.h"
#import "STKConstants.h"

%hook SBIconView

%new
- (void)addGroupView:(STKGroupView *)groupView
{
    objc_setAssociatedObject(self, @selector(STKGroupView), groupView, OBJC_ASSOCIATION_RETAIN);
    [self addSubview:groupView];
    [self sendSubviewToBack:groupView];
}

%new 
- (void)removeGroupView
{
    STKGroupView *view = objc_getAssociatedObject(self, @selector(STKGroupView));
    [view removeFromSuperview];
    objc_setAssociatedObject(self, @selector(STKGroupView), nil, OBJC_ASSOCIATION_RETAIN);
}

%end
