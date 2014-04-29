#import "SBIconView+Apex.h"
#import "STKConstants.h"

static NSString * const CheckOverlayImageName = @"OverlayCheck@2x";
static NSString * const AddOverlayImageName = @"OverlayAdd@2x";

#define kHomeScreenOverlayBlurStyle 7
#define kFolderOverlayBlurStyle     2

@interface SBIconView (ApexPrivate)
+ (UIBezierPath *)pathForApexCrossOverlayWithBounds:(CGRect)bounds;
+ (CALayer *)maskForApexEmptyIconOverlayWithBounds:(CGRect)bounds;

@property (nonatomic, retain) UIView *apexOverlayView;
- (void)removeGroupView;
- (void)stk_modifyOverlayViewForFolderIfNecessary;
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
    overlayView.alpha = 0;
    [[self _iconImageView] addSubview:overlayView];
    [self setNeedsLayout];
    overlayView.alpha = 1.f;
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
    if (type == STKOverlayTypeEditing || type == STKOverlayTypeCheck) {
        NSString *imageName = ((type == STKOverlayTypeEditing) ? AddOverlayImageName : CheckOverlayImageName);
        overlayView = [[[UIImageView alloc] initWithImage:UIIMAGE_NAMED(imageName)] autorelease];
        overlayView.contentMode = UIViewContentModeCenter;
        overlayView.frame = [self _iconImageView].bounds;
    }
    else {
        overlayView = [[[CLASS(STKWallpaperBlurView) alloc] initWithWallpaperVariant:SBWallpaperVariantHomeScreen] autorelease];
        overlayView.frame = [self _iconImageView].bounds;
        [(STKWallpaperBlurView *)overlayView setStyle:kHomeScreenOverlayBlurStyle];
        ((STKWallpaperBlurView *)overlayView).mask = [[self class] maskForApexEmptyIconOverlayWithBounds:overlayView.layer.bounds];
    }
    self.apexOverlayView = overlayView;
    if (!(type == STKOverlayTypeEditing || type == STKOverlayTypeCheck)) {
        [self bringSubviewToFront:[self _iconImageView]];
    }
    [self stk_modifyOverlayViewForFolderIfNecessary];
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

%new
- (void)stk_modifyOverlayViewForFolderIfNecessary
{
    BOOL isEmptyOrPlaceholderIcon = ([self.icon isKindOfClass:CLASS(STKEmptyIcon)]
                                  || [self.icon isKindOfClass:CLASS(STKPlaceholderIcon)]);
    if (self.containerGroupView && isEmptyOrPlaceholderIcon) {
        BOOL isInFolder = (((SBIconView *)self.containerGroupView.superview).location == SBIconLocationFolder);
        if (isInFolder) {
            [(STKWallpaperBlurView *)self.apexOverlayView setStyle:kFolderOverlayBlurStyle];
        }
    }
}

- (void)layoutSubviews
{
    %orig();
    [self sendSubviewToBack:[self groupView]];
}

- (void)setIcon:(SBIcon *)icon
{
    %orig(icon);
    BOOL isEmptyOrPlaceholderIcon = ([self.icon isKindOfClass:CLASS(STKEmptyIcon)]
                                  || [self.icon isKindOfClass:CLASS(STKPlaceholderIcon)]);
    if (isEmptyOrPlaceholderIcon) {
        [self showApexOverlayOfType:STKOverlayTypeEmpty];
        [self stk_modifyOverlayViewForFolderIfNecessary];
    }
    else {
        [self removeApexOverlay];
    }
}

- (void)didMoveToSuperview
{
    [self stk_modifyOverlayViewForFolderIfNecessary];
    %orig();
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
    STKGroupView *activeGroupView = 
        ([STKGroupController sharedController].openGroupView ?: [STKGroupController sharedController].openingGroupView);

    if ([self groupView] != activeGroupView) {
        return %orig(point, event);
    }
    view = [self.groupView hitTest:point withEvent:event] ?: %orig();
    
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
