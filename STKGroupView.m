#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "STKGroupView.h"

#undef CLASS
#define CLASS(cls) NSClassFromString(@#cls)

#define kCentralIconPreviewScale 0.95f
#define kSubappScale             0.81f
#define kBandingAllowance        0.0

#define KEYFRAME_DURATION() (1.0 + (kBandingAllowance / [self _targetDistance]))

typedef NS_ENUM(NSInteger, STKRecognizerDirection) {
    STKRecognizerDirectionNone,
    STKRecognizerDirectionUp,
    STKRecognizerDirectionDown
};

@implementation STKGroupView
{
    STKGroup *_group;
    SBIconView *_centralIconView;
    STKGroupLayout *_subappLayout;
    STKGroupLayout *_displacedIconLayout;
    UIPanGestureRecognizer *_panRecognizer;
    UITapGestureRecognizer *_tapRecognizer;

    BOOL _isOpen;

    NSMapTable *_pathCache;
}

- (instancetype)initWithGroup:(STKGroup *)group
{
    if ((self = [super initWithFrame:CGRectZero])) {
        _group = [group retain];
        _activationMode = STKActivationModeSwipeUpAndDown;
        self.alpha = 0.f;
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

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    for (SBIconView *iconView in _subappLayout) {
        if ([iconView pointInside:[self convertPoint:point toView:iconView] withEvent:event]) {
            return iconView;
        }
    }
    return nil;
}

- (void)open
{
    [self _animateOpenWithCompletion:nil];
}

- (void)close
{
    [self _animateClosedWithCompletion:nil];
}

#pragma mark - Config
- (void)configureSuperview
{
    _centralIconView = [[CLASS(SBIconViewMap) homescreenMap] iconViewForIcon:_group.centralIcon];
    [self _configureSubappViews];
    [self layoutSubviews];

    _panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panned:)];
    _panRecognizer.delegate = self;

    _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_doubleTapped:)];
    _tapRecognizer.numberOfTapsRequired = 2;
    _tapRecognizer.delegate = self;

    [_centralIconView addGestureRecognizer:_panRecognizer];
    [_centralIconView addGestureRecognizer:_tapRecognizer];

    self.alpha = 1.f;
}

- (void)_configureSubappViews
{
    _subappLayout = [[STKGroupLayout alloc] init];
    [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
        SBIconView *iconView = [[[CLASS(SBIconView) alloc] initWithDefaultSize] autorelease];
        iconView.frame = (CGRect){self.center, iconView.frame.size};
        iconView.icon = icon;
        iconView.delegate = self.delegate;
        [_subappLayout addIcon:iconView toIconsAtPosition:pos];
        [self _setAlpha:0.f forLabelOfIconView:iconView];
        [self addSubview:iconView];
        [self sendSubviewToBack:iconView];
    }];
    _displacedIconLayout = [[STKGroupLayoutHandler layoutForIconsToDisplaceAroundIcon:_group.centralIcon usingLayout:_group.layout] retain];
}

#pragma mark - Gesture Handling
- (void)_panned:(UIPanGestureRecognizer *)recognizer
{
    static CGFloat targetDistance = 0.f;
    static CGFloat keyframeDuration = 0.f;

    double distance = fabs([recognizer translationInView:self].y);
    CGFloat realOffset = MIN((distance / targetDistance), 1.0);
    CFTimeInterval offset = MIN(distance / (targetDistance + kBandingAllowance), keyframeDuration - 0.00001);
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        keyframeDuration = KEYFRAME_DURATION();
        targetDistance = [self _targetDistance];
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged) {
        [self _moveAllIconsToOffset:offset performingBlockOnSubApps:^(SBIconView *iconView) {
            [self _setAlpha:realOffset forLabelOfIconView:iconView];
        }];
        [self _setAlphaForOtherIcons:(1.2 - realOffset)];
    }
    else if (recognizer.state == UIGestureRecognizerStateEnded) {
        if (realOffset > 0.5f) {
            [self _animateOpenWithCompletion:nil];
        }
        else {
            [self _animateClosedWithCompletion:nil];
        }
        targetDistance = 0.f;
    }
}

- (void)_doubleTapped:(UITapGestureRecognizer *)recog
{

}

#pragma mark - Moving
- (void)_moveAllIconsToOffset:(CFTimeInterval)timeOffset performingBlockOnSubApps:(void(^)(SBIconView *))block
{
    void(^mover)(SBIconView *, STKLayoutPosition, NSArray *, NSUInteger, CGPoint target) = 
    ^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, CGPoint target) {
        if (!iconView) {
            return;
        }
        UIBezierPath *path = ({
            UIBezierPath *path = [self _cachedPathForIcon:iconView.icon];
            if (!path) {
                target = [self _pointByApplyingBandingToPoint:target withPosition:position];
                path = [self _pathForIconToPoint:target fromIconView:iconView];
                [self _cachePath:path forIcon:iconView.icon];
            }
            path;
        });
        CAKeyframeAnimation *animation = [self _defaultAnimation];
        animation.path = path.CGPath;
        animation.timeOffset = timeOffset;
        iconView.layer.position = [(CALayer *)iconView.layer.presentationLayer position];
        [iconView.layer addAnimation:animation forKey:@"ApexIconMoveAnimation"];
    };

    [_subappLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iv, STKLayoutPosition pos, NSArray *c, NSUInteger i, BOOL *s) {
        if (block) {
            block(iv);
        }
        CGPoint target = [self _targetPositionForSubappSlot:(STKGroupSlot){pos, i}];
        mover(iv, pos, c, i, target);
    }];
    SBIconListView *listView = STKListViewForIcon(_group.centralIcon);
    [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger i, BOOL *s) {
        SBIconView *iv = [listView viewForIcon:icon];
        CGPoint target = [self _displacedOriginForIcon:iv.icon withPosition:pos];
        mover(iv, pos, c, i, target);
    }];
}

- (CAKeyframeAnimation *)_defaultAnimation
{
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    animation.duration = KEYFRAME_DURATION();
    animation.speed = 0.0;
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    return animation;
}

- (UIBezierPath *)_pathForIconToPoint:(CGPoint)destination fromIconView:(SBIconView *)iconView
{
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:iconView.layer.position];
    [path addLineToPoint:destination];
    return path;
}

#pragma mark - Animate
- (void)_animateOpenWithCompletion:(void(^)(void))completion
{
    if ([self.delegate respondsToSelector:@selector(groupViewWillOpen:)]) {
        [self.delegate groupViewWillOpen:self];
    }
    [UIView animateWithDuration:0.22f animations:^{
        SBIconListView *listView = STKListViewForIcon(_group.centralIcon);
        [self _setAlphaForOtherIcons:0.2f];

        [_subappLayout enumerateIconsUsingBlockWithIndexes:
            ^(SBIconView *iconView, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                CGPoint destination = ({
                    CGPoint dest = CGPointZero;
                    UIBezierPath *path = [self _cachedPathForIcon:iconView.icon];
                    if (path) {
                        // Use the endpoint for the cached path, since calculating manually again would yield wrong results.
                        dest = path.currentPoint;
                        // However, the path is at target+banding allowance, so substract that
                        dest = [self _pointByRemovingBandingFromPoint:dest withPosition:pos];
                    }
                    else {
                        // The path is nil, meaning the icons haven't been moved yet, so we can use manual calculation
                        dest = [self _targetPositionForSubappSlot:(STKGroupSlot){pos, idx}];;
                    }
                    dest;
                });
                [self _setAlpha:1.f forLabelOfIconView:iconView];
                iconView.layer.position = destination;
                [iconView.layer removeAnimationForKey:@"ApexIconMoveAnimation"];
            }    
        ];
        [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:
            ^(SBIcon *icon, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                SBIconView *iconView = [listView viewForIcon:icon];
                CGPoint destination = ({
                    CGPoint dest;
                    UIBezierPath *path = [self _cachedPathForIcon:iconView.icon];
                    if (path) {
                        dest = path.currentPoint;
                        dest = [self _pointByRemovingBandingFromPoint:dest withPosition:pos];
                    }
                    else {
                        dest = [self _displacedOriginForIcon:icon withPosition:pos];
                    }
                    dest;
                });
                iconView.layer.position = destination;
                [iconView.layer removeAnimationForKey:@"ApexIconMoveAnimation"];
            }
        ];
    } completion:^(BOOL finished) {
        if (finished) {
            if (completion) {
                completion();
            }
            _isOpen = YES;
            if ([self.delegate respondsToSelector:@selector(groupViewDidOpen:)]) {
                [self.delegate groupViewDidOpen:self];
            }
        }
    }];
}

- (void)_animateClosedWithCompletion:(void(^)(void))completion
{
    if ([self.delegate respondsToSelector:@selector(groupViewWillClose:)]) {
        [self.delegate groupViewWillClose:self];
    }
    [UIView animateWithDuration:0.22f animations:^{
        SBIconListView *listView = STKListViewForIcon(_group.centralIcon);
        [self _setAlphaForOtherIcons:1.f];

        [_subappLayout enumerateIconsUsingBlockWithIndexes:
            ^(SBIconView *iconView, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                [self _setAlpha:0.f forLabelOfIconView:iconView];
                iconView.frame = (CGRect){CGPointZero, iconView.frame.size};
                [iconView.layer removeAnimationForKey:@"ApexIconMoveAnimation"];
            }    
        ];
        [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:
            ^(SBIcon *icon, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                SBIconView *iconView = [listView viewForIcon:icon];
                iconView.frame = (CGRect){[listView originForIcon:icon], iconView.frame.size};
                [iconView.layer removeAnimationForKey:@"ApexIconMoveAnimation"];
            }
        ];
    } completion:^(BOOL finished) {
        if (finished) {
            if (completion) {
                completion();
            }
            _isOpen = NO;
            if ([self.delegate respondsToSelector:@selector(groupViewDidClose:)]) {
                [self.delegate groupViewDidClose:self];
            }
        }
    }];
}


#pragma mark - Cache Handling
- (void)_cachePath:(UIBezierPath *)path forIcon:(SBIcon *)icon
{
    NSParameterAssert(path);
    NSParameterAssert(icon.nodeIdentifier);
    if (!_pathCache) _pathCache = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory valueOptions:NSPointerFunctionsCopyIn capacity:0];
    [_pathCache setObject:path forKey:icon.nodeIdentifier];

    CLog(@"Caching path for icon %@.. Count: %zd", icon.nodeIdentifier, [[_pathCache objectEnumerator] allObjects].count);
}

- (UIBezierPath *)_cachedPathForIcon:(SBIcon *)subOrDisplacedIcon
{
    return [_pathCache objectForKey:subOrDisplacedIcon.nodeIdentifier];
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

- (CGPoint)_pointByApplyingBandingToPoint:(CGPoint)point withPosition:(STKLayoutPosition)position
{
    CGFloat allowance = kBandingAllowance * ((position == STKPositionTop || position == STKPositionLeft) ? -1.f : 1.f);
    if (STKPositionIsVertical(position)) {
        return (CGPoint){point.x, point.y + allowance};
    }
    return (CGPoint){point.x + allowance, point.y};
}

- (CGPoint)_pointByRemovingBandingFromPoint:(CGPoint)point withPosition:(STKLayoutPosition)position
{
    CGFloat allowance = kBandingAllowance * ((position == STKPositionTop || position == STKPositionLeft) ? -1.f : 1.f);
    if (STKPositionIsVertical(position)) {
        return (CGPoint){point.x, point.y - allowance};
    }
    return (CGPoint){point.x - allowance, point.y};
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

- (double)_targetDistance
{
    CGFloat defaultHeight = [objc_getClass("SBIconView") defaultIconSize].height;
    CGFloat verticalPadding = [STKListViewForIcon(_group.centralIcon) stk_realVerticalIconPadding];
    return verticalPadding + defaultHeight;
}

@end
