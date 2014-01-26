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

%new
- (STKGroupView *)containerGroupView
{
    if ([self.superview isKindOfClass:[STKGroupView class]]) {
        return (STKGroupView *)self.superview;
    }
    return nil;
}

%new
- (void)setApexOverlayView:(STKIconOverlayView *)overlayView
{
    [[self apexOverlayView] removeFromSuperview];
    objc_setAssociatedObject(self, @selector(STKOverlayView), overlayView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addSubview:overlayView];
}

%new
- (STKIconOverlayView *)apexOverlayView
{
    return objc_getAssociatedObject(self, @selector(STKOverlayView));
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

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *view = nil;
    if (CGRectContainsPoint(self.bounds, point) && ![self groupView].isOpen) {
        view = self;
    }
    else {
        view = [[self groupView] hitTest:point withEvent:event] ?: %orig();
    }
    return view;
}

static const CGFloat kLineLength = 23.f;
static const CGFloat kHalfLength = kLineLength * 0.5f;
static const CGFloat kLineWidth  = 3.f;
- (void)setIcon:(SBIcon *)icon
{
    %orig(icon);
    if (![icon isKindOfClass:objc_getClass("STKEmptyIcon")]) {
        [self setApexOverlayView:nil];
        return;
    }
    
    STKIconOverlayView *overlayView = [[[STKIconOverlayView alloc] initWithFrame:(CGRect){{0, 0}, {60.f, 60.f}}] autorelease];
    [self setApexOverlayView:overlayView];
    overlayView.layer.masksToBounds = YES;
    overlayView.blurRadius = 5.f;
    overlayView.center = [self _iconImageView].center;
    overlayView.layer.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.5f].CGColor;

    CGRect bounds = overlayView.layer.bounds;
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = bounds;
    maskLayer.fillColor = [UIColor blackColor].CGColor;
    
    CGPoint position = (CGPoint){(bounds.size.width * 0.5f), (bounds.size.height * 0.5f)};    
    CGRect vertical = (CGRect){{position.x - kLineWidth * 0.5, position.y - kHalfLength}, {kLineWidth, kLineLength}};
    CGRect horizontal = (CGRect){{vertical.origin.y, vertical.origin.x}, {kLineLength, kLineWidth}};
    CGRect intersection = CGRectIntersection(vertical, horizontal);
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:vertical];
    [path appendPath:[UIBezierPath bezierPathWithRect:horizontal]];
    [path appendPath:[UIBezierPath bezierPathWithRect:intersection]];
    [path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 8.f, 8.f)]];

    maskLayer.path = path.CGPath;
    maskLayer.fillRule = kCAFillRuleEvenOdd;

    overlayView.layer.mask = maskLayer;
}

%end
