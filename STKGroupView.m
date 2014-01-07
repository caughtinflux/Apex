#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "STKGroupView.h"

#undef CLASS
#define CLASS(cls) NSClassFromString(@#cls)


static NSString * const LabelAlphaAnimationKey = @"ApexLabelAlphaAnimation";
static NSString * const IconScaleAnimationKey  = @"ApexIconScaleAnimation";

@implementation STKGroupView
{
    STKGroup *_group;
    SBIconView *_centralIconView;
    STKGroupLayout *_subappLayout;
    STKGroupLayout *_displacedIconLayout;
    UIPanGestureRecognizer *_panRecognizer;
    UITapGestureRecognizer *_tapRecognizer;

    NSMutableDictionary *_pathCache;
}

- (instancetype)initWithGroup:(STKGroup *)group
{
    if ((self = [super initWithFrame:CGRectZero])) {
        _group = [group retain];
        _centralIconView = [[CLASS(SBIconViewMap) homescreenMap] iconViewForIcon:_group.centralIcon];
        [self _configureCentralIconView];
        [self _configureSubappViews];
        [self layoutSubviews];

        _activationMode = STKActivationModeSwipeUpAndDown;
    }
    return self;
}

- (void)dealloc
{
    [self _invalidatePathCache];
    [_panRecognizer.view removeGestureRecognizer:_panRecognizer];
    [_tapRecognizer.view removeGestureRecognizer:_tapRecognizer];

    [_panRecognizer release];
    [_tapRecognizer release];
    [_group release];

    [super dealloc];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.frame = self.superview.bounds;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    for (SBIconView *iconView in _subappLayout) {
        if ([iconView pointInside:[self convertPoint:point toView:iconView] withEvent:event]) {
            return YES;
        }
    }
    return NO;
}

- (void)open
{
}

- (void)close
{

}

#pragma mark - Config
- (void)_configureCentralIconView
{
    _panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panned:)];
    _panRecognizer.delegate = self;

    _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_doubleTapped:)];
    _tapRecognizer.numberOfTapsRequired = 2;
    _tapRecognizer.delegate = self;

    [_centralIconView addGestureRecognizer:_panRecognizer];
    [_centralIconView addGestureRecognizer:_tapRecognizer];
    
    [_centralIconView addSubview:self];
    [_centralIconView sendSubviewToBack:self];
}

- (void)_configureSubappViews
{
    _subappLayout = [[STKGroupLayout alloc] init];
    [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
        SBIconView *iconView = [[[CLASS(SBIconView) alloc] initWithDefaultSize] autorelease];
        iconView.frame = (CGRect){self.center, iconView.frame.size};
        iconView.icon = icon;
        [_subappLayout addIcon:iconView toIconsAtPosition:pos];
        [self _setAlpha:0.f forLabelOfIconView:iconView];
        [self addSubview:iconView];
    }];
    _displacedIconLayout = [[STKGroupLayoutHandler layoutForIconsToDisplaceAroundIcon:_group.centralIcon usingLayout:_group.layout] retain];
}

- (void)_panned:(UIPanGestureRecognizer *)recognizer
{
    static CGFloat targetDistance = 0.f;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        CGFloat defaultHeight = [objc_getClass("SBIconView") defaultIconSize].height;
        CGFloat verticalPadding = [STKListViewForIcon(_group.centralIcon) stk_realVerticalIconPadding];
        targetDistance = verticalPadding + defaultHeight;
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged) {
        // FIXME: Animation resets at 1.0, I KNOW A FIX EXISTS
        CFTimeInterval offset = MIN((fabsf([recognizer translationInView:self].y) / targetDistance), 0.99f);
        [self _moveSubappsToOffset:offset];
        [self _moveDisplacedIconsToOffset:offset];
        [self _setAlphaForOtherIcons:(1.2 - offset)];
    }
}

- (void)_moveSubappsToOffset:(CFTimeInterval)timeOffset
{
    [_subappLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL *stop) {
        UIBezierPath *path = ({
            UIBezierPath *path = [self _cachedPathForIcon:iconView.icon];
            if (!path) {
                path = [UIBezierPath bezierPath];
                [path moveToPoint:iconView.layer.position];
                [path addLineToPoint:[self _targetPositionForSubappSlot:(STKGroupSlot){position, index}]];

                [self _cachePath:path forIcon:iconView.icon];
            }
            path;
        }); 

        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        animation.duration = 1.0;
        animation.speed = 0.0;
        animation.fillMode = kCAFillModeForwards;
        animation.removedOnCompletion = NO;
        animation.path = path.CGPath;
        animation.timeOffset = timeOffset;
        [iconView.layer addAnimation:animation forKey:@"ApexSubappAnimation"];

        [self _setAlpha:timeOffset forLabelOfIconView:iconView];
    }];
}

- (void)_moveDisplacedIconsToOffset:(CFTimeInterval)timeOffset
{
    [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL *stop) {
        SBIconView *iconView = [self _iconViewForIcon:icon];
        UIBezierPath *path = ({
            UIBezierPath *path = [self _cachedPathForIcon:iconView.icon];
            if (!path) {
                path = [UIBezierPath bezierPath];
                [path moveToPoint:iconView.layer.position];
                [path addLineToPoint:[self _displacedOriginForIcon:icon withPosition:position]];

                [self _cachePath:path forIcon:iconView.icon];
            }
            path;
        });
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        animation.duration = 1.0;
        animation.speed = 0.0;
        animation.fillMode = kCAFillModeForwards;
        animation.removedOnCompletion = NO;
        animation.path = path.CGPath;
        animation.timeOffset = timeOffset;
        [iconView.layer addAnimation:animation forKey:@"ApexDisplacedIconAnimation"];
    }];
}

#pragma mark - Cache Handling
- (void)_cachePath:(UIBezierPath *)path forIcon:(SBIcon *)icon
{
    NSParameterAssert(path);
    NSParameterAssert(icon.leafIdentifier);
    if (!_pathCache) _pathCache = [NSMutableDictionary new];
    _pathCache[icon.leafIdentifier] = path;

    CLog(@"Caching %@.. Count: %zd", path, [_pathCache allKeys].count);
}

- (UIBezierPath *)_cachedPathForIcon:(SBIcon *)subOrDisplacedIcon
{
    NSParameterAssert(subOrDisplacedIcon.leafIdentifier);
    return _pathCache[subOrDisplacedIcon.leafIdentifier];
}

- (void)_invalidatePathCache
{
    [_pathCache release];
    _pathCache = nil;
}


#pragma mark - Coordinate Calculations
- (CGPoint)_targetPositionForSubappSlot:(STKGroupSlot)slot
{
    CGFloat negator = ((slot.position == STKPositionTop || slot.position == STKPositionLeft) ? -1.f : 1.f);
    CGFloat factor = (slot.index + 1) * negator;
    CGPoint target = [self.subviews[0] layer].position;
    CGSize iconSize = [CLASS(SBIconView) defaultIconSize];
    SBIconListView *listView = STKListViewForIcon(_group.centralIcon);
    if (slot.position == STKPositionTop || slot.position == STKPositionBottom) {
        target.y += ([listView stk_realVerticalIconPadding] + iconSize.height) * factor;
    }
    else if (slot.position == STKPositionLeft || slot.position == STKPositionRight) {
        target.x += ([listView stk_realHorizontalIconPadding] + iconSize.width) * factor;
    }
    return target;
}

- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position
{
    // Calculate the positions manually
    SBIconListView *listView = STKListViewForIcon(_group.centralIcon);
    SBIconView *iconView = [self _iconViewForIcon:icon];
    STKGroupLayout *layout = _group.layout;
    
    CGPoint originalOrigin = [listView viewForIcon:icon].layer.position; 
    CGRect originalFrame = (CGRect){originalOrigin, {iconView.frame.size.width, iconView.frame.size.height}};
    CGPoint returnPoint = originalOrigin;
    NSInteger multiplicationFactor = [layout[position] count];
    CGFloat negator = ((position == STKPositionTop || position == STKPositionLeft) ? -1.f : 1.f);
    if (position == STKPositionTop || position == STKPositionBottom) {
        returnPoint.y = (originalFrame.origin.y + ((originalFrame.size.height + [listView stk_realVerticalIconPadding]) * multiplicationFactor * negator));
    }
    else if (position == STKPositionLeft || position == STKPositionRight) {
        returnPoint.x = (originalFrame.origin.x + ((originalFrame.size.width + [listView stk_realHorizontalIconPadding]) * multiplicationFactor * negator));
    }
    return returnPoint;
}

- (void)_setAlphaForOtherIcons:(CGFloat)alpha
{
    void(^setter)(id, id) = ^(SBIconListView *listView, SBIcon *icon){
        if (icon == _group.centralIcon) {
            return;
        }
        SBIconView *view = [listView viewForIcon:icon];
        view.alpha = alpha;
        [self _setAlpha:alpha forLabelOfIconView:[listView viewForIcon:icon]];
    };
    SBIconListView *listView = STKListViewForIcon(_group.centralIcon);
    for (SBIcon *icon in [listView icons]) {
        setter(listView, icon);
    }
    for (SBIcon *icon in [[[CLASS(SBIconController) sharedInstance] dockListView] icons]) {
        setter([[CLASS(SBIconController) sharedInstance] dockListView], icon);
    }
}

- (void)_setAlpha:(CGFloat)alpha forLabelOfIconView:(SBIconView *)iconView
{
    UIView *view = [iconView valueForKey:@"_labelView"];
    view.alpha = alpha;
}

- (SBIconView *)_iconViewForIcon:(SBIcon *)icon
{
    return [[CLASS(SBIconViewMap) homescreenMap] mappedIconViewForIcon:icon];
}

@end
