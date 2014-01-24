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

- (void)setIcon:(SBIcon *)icon
{
    %orig(icon);
    if (![icon isKindOfClass:objc_getClass("STKEmptyIcon")]) {
        [self setApexOverlayView:nil];
        return;
    }
    STKIconOverlayView *overlayView = [[[STKIconOverlayView alloc] initWithFrame:[[self _iconImageView] frame]] autorelease];
    [self setApexOverlayView:overlayView];
    overlayView.layer.cornerRadius = (overlayView.layer.bounds.size.height * 0.5f);
    overlayView.layer.masksToBounds = YES;
    overlayView.blurRadius = 5.f;
    [overlayView setBackgroundColor:[UIColor colorWithWhite:1.f alpha:0.6]];

    CGRect bounds = overlayView.layer.bounds;
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = bounds;
    maskLayer.fillColor = [UIColor blackColor].CGColor;
    
    const CGFloat kLineLength = 23.f;
    const CGFloat kHalfLength = kLineLength * 0.5f;
    const CGFloat kLineWidth = 3.f;
    CGPoint position = (CGPoint){(bounds.size.width * 0.5f), (bounds.size.height * 0.5f)};
    CGPoint verticalOrigin = (CGPoint){position.x, (position.y - kHalfLength)};
    CGPoint horizontalOrigin = (CGPoint){verticalOrigin.y, verticalOrigin.x};

    CGRect vertical = (CGRect){verticalOrigin, {kLineWidth, kLineLength}};
    CGRect horizontal = (CGRect){horizontalOrigin, {kLineLength, kLineWidth}};
    //CGRect intersection = CGRectIntersection(vertical, horizontal);
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:vertical];
    [path appendPath:[UIBezierPath bezierPathWithRect:horizontal]];
    //[path appendPath:[UIBezierPath bezierPathWithRect:intersection]];
    [path appendPath:[UIBezierPath bezierPathWithRect:bounds]];

    maskLayer.path = path.CGPath;
    maskLayer.fillRule = kCAFillRuleEvenOdd;

    overlayView.layer.mask = maskLayer;
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

%end
