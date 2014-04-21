#import "SBIconView+Apex.h"
#import "STKConstants.h"

@interface SBIconView (ApexPrivate)
+ (UIBezierPath *)pathForApexCrossOverlayWithBounds:(CGRect)bounds;
+ (CALayer *)maskForApexEmptyIconOverlayWithBounds:(CGRect)bounds;
+ (CALayer *)maskForApexEditingOverlayWithBounds:(CGRect)bounds;

@property (nonatomic, retain) UIView *apexOverlayView;
- (void)removeGroupView;
@end

%hook SBIconView

%new
+ (UIBezierPath *)pathForApexCrossOverlayWithBounds:(CGRect)bounds
{
    static const CGFloat kLineLength = 23.f;
    static const CGFloat kHalfLength = kLineLength * 0.5f;
    static const CGFloat kLineWidth  = 3.f;

    CGPoint position = (CGPoint){(bounds.size.width * 0.5f), (bounds.size.height * 0.5f)};    
    CGRect vertical = (CGRect){{position.x - kLineWidth * 0.5, position.y - kHalfLength}, {kLineWidth, kLineLength}};
    CGRect horizontal = (CGRect){{vertical.origin.y, vertical.origin.x}, {kLineLength, kLineWidth}};
    CGRect intersection = CGRectIntersection(vertical, horizontal);
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:vertical];
    [path appendPath:[UIBezierPath bezierPathWithRect:horizontal]];
    [path appendPath:[UIBezierPath bezierPathWithRect:intersection]];
    return path;
}

%new
+ (CALayer *)maskForApexEmptyIconOverlayWithBounds:(CGRect)bounds
{
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = bounds;
    maskLayer.strokeColor = [UIColor clearColor].CGColor;
    maskLayer.fillColor = [UIColor blackColor].CGColor;
    
    UIBezierPath *cross = [[self class] pathForApexCrossOverlayWithBounds:bounds];
    [cross appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 8.f, 8.f)]];

    maskLayer.path = cross.CGPath;
    maskLayer.fillRule = kCAFillRuleEvenOdd;

    return maskLayer;
}

%new
+ (CALayer *)maskForApexEditingOverlayWithBounds:(CGRect)bounds
{
    bounds.size.width -= 2.0f;
    bounds.size.height -= 2.0f;
    bounds.origin.x += 0.5f;
    bounds.origin.y += 0.5f;

    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = bounds;
    maskLayer.strokeColor = [UIColor clearColor].CGColor;
    maskLayer.fillColor = [UIColor blackColor].CGColor;
    
    UIBezierPath *cross = [[self class] pathForApexCrossOverlayWithBounds:bounds];
    cross.lineWidth = 1.f;
    [cross appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 8.f, 8.f)]];
    UIBezierPath *outerCircle = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 6.f, 6.f)];
    outerCircle.lineWidth = 1.f;
    [cross appendPath:outerCircle];
    [cross appendPath:[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:[%c(SBIconImageView) cornerRadius]]];
    maskLayer.path = cross.CGPath;
    maskLayer.fillRule = kCAFillRuleEvenOdd;
    return maskLayer;
}

%new
- (void)setGroupView:(STKGroupView *)groupView
{
    [self removeGroupView];
    groupView.frame = self.bounds;
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
    view.frame = self.bounds;
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
- (void)setApexOverlayView:(UIView *)overlayView
{
    [self.apexOverlayView removeFromSuperview];
    objc_setAssociatedObject(self, @selector(STKOverlayView), overlayView, OBJC_ASSOCIATION_ASSIGN);
    [self addSubview:overlayView];
    [self setNeedsLayout];
}

%new
- (UIView *)apexOverlayView
{
    return objc_getAssociatedObject(self, @selector(STKOverlayView));
}

%new
- (void)showApexOverlayOfType:(STKOverlayType)type
{
    UIView *overlayView = nil;
    CALayer *mask = nil;
    BOOL isEditingOverlay = (type == STKOverlayTypeEditing);
    if (isEditingOverlay) {
        overlayView = [[[UIView alloc] initWithFrame:[self _iconImageView].frame] autorelease];
        mask = [[self class] maskForApexEditingOverlayWithBounds:overlayView.layer.bounds];
        overlayView.layer.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f].CGColor;
    }
    else {
        overlayView = [[[CLASS(SBFolderBackgroundView) alloc] initWithFrame:[self _iconImageView].frame] autorelease];
        mask = [[self class] maskForApexEmptyIconOverlayWithBounds:overlayView.layer.bounds];
    }
    overlayView.layer.mask = mask;
    self.apexOverlayView = overlayView;
    if (!isEditingOverlay) {
        [self bringSubviewToFront:[self _iconImageView]];
    }
}

%new
- (void)removeApexOverlay
{
    self.apexOverlayView = nil;
}

%new
- (void)stk_setImageViewScale:(CGFloat)scale
{
    [self _iconImageView].layer.transform = CATransform3DMakeScale(scale, scale, scale);
}

- (void)layoutSubviews
{
    %orig();
    self.apexOverlayView.frame = (CGRect){{-1.f, -1.f}, self.apexOverlayView.frame.size};
}

- (void)setIcon:(SBIcon *)icon
{
    %orig(icon);
    if ([icon isKindOfClass:CLASS(STKEmptyIcon)] || [icon isKindOfClass:CLASS(STKPlaceholderIcon)]) {
        [self showApexOverlayOfType:STKOverlayTypeEmpty];   
    }
    else {
        [self removeApexOverlay];
    }
}

- (void)setAlpha:(CGFloat)alpha
{
    %orig(alpha);

    static const CGFloat prevMax = 1.0f;
    static const CGFloat prevMin = 0.2;
    static const CGFloat newMax = 1.0f;
    static const CGFloat newMin = 0.0f;
    CGFloat groupAlpha = STKScaleNumber(alpha, prevMin, prevMax, newMin, newMax);
    [self.groupView setAlpha:groupAlpha];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *view = nil;
    if ([self groupView].isOpen == NO) {
        return %orig(point, event);
    }
    else {
        view = [self.groupView hitTest:point withEvent:event] ?: %orig();
    }
    return view;
}

- (void)dealloc
{
    self.groupView = nil;
    %orig();
}
%end

#pragma mark - SBIconImageView
%hook SBIconImageView
- (UIImage *)darkeningOverlayImage
{
    static UIImage *emptyIconDarkeningOverlay;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        CGRect bounds = self.bounds;
        CALayer *mask = [CLASS(SBIconView) maskForApexEmptyIconOverlayWithBounds:bounds];
        UIGraphicsBeginImageContextWithOptions(bounds.size, NO, 0);
        [mask renderInContext:UIGraphicsGetCurrentContext()];
        emptyIconDarkeningOverlay = [UIGraphicsGetImageFromCurrentImageContext() retain];
        UIGraphicsEndImageContext();
    });
    return ([self.icon isKindOfClass:CLASS(STKEmptyIcon)] || [self.icon isKindOfClass:CLASS(STKPlaceholderIcon)] 
            ? emptyIconDarkeningOverlay : %orig());
}
%end

%ctor
{
    %init();
}
