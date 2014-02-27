#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "STKGroupView.h"
#import "STKConstants.h"

#undef CLASS
#define CLASS(cls) NSClassFromString(@#cls)

#define kSubappScale      0.81f
#define kBandingAllowance 20.f

#define KEYFRAME_DURATION() (1.0 + (kBandingAllowance / _targetDistance))

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
    NSSet *_iconsHiddenForPlaceholders;
    NSMapTable *_pathCache;

    BOOL _needsCreation;
    BOOL _isOpen;
    BOOL _showPreview;
    BOOL _isAnimating;
    BOOL _ignoreRecognizer;
    CGFloat _targetDistance;
    CGFloat _keyframeDuration;
    STKRecognizerDirection _recognizerDirection;

    struct {
        NSUInteger didMoveToOffset:1;
        NSUInteger willOpen:1;
        NSUInteger didOpen:1;
        NSUInteger willClose:1;
        NSUInteger didClose:1;
    } _delegateFlags;
}

- (instancetype)initWithGroup:(STKGroup *)group
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.group = group;
        _activationMode = STKActivationModeSwipeUpAndDown;
        _showPreview = YES;
        self.alpha = 0.f;
    }
    return self;
}

- (void)dealloc
{
    if ([_delegate respondsToSelector:@selector(groupViewWillBeDestroyed:)]) {
        [_delegate groupViewWillBeDestroyed:self];
    }
    [self resetLayouts];
    [self _removeGestureRecognizers];
    self.group = nil;
    [super dealloc];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (_isOpen) {
        for (SBIconView *iconView in _subappLayout) {
            if ([iconView pointInside:[self convertPoint:point toView:iconView] withEvent:event]) {
                return iconView;
            }
        }
    }
    return [super hitTest:point withEvent:event];
}

#pragma mark - Public Methods
- (void)open
{
    [self _animateOpenWithCompletion:nil];
}

- (void)close
{
    [self _animateClosedWithCompletion:nil];
}

- (void)resetLayouts
{
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];   
    [_subappLayout release];
    _subappLayout = nil;
    [_displacedIconLayout release];
    _displacedIconLayout = nil;
    [self _invalidatePathCache];
}

- (SBIconView *)subappIconViewForIcon:(SBIcon *)icon
{
    SBIconView *iconView = nil;
    for (iconView in _subappLayout) {
        if (iconView.icon == icon) {
            break;
        }
    }
    return iconView;
}

- (void)setGroup:(STKGroup *)group
{
    [_group removeObserver:self];
    [_group release];
    _group = [group retain];
    [_group addObserver:self];
    [self resetLayouts];
    _centralIconView = [[CLASS(SBIconViewMap) homescreenMap] iconViewForIcon:_group.centralIcon];
}

- (void)setDelegate:(id<STKGroupViewDelegate>)delegate
{
    _delegate = delegate;
    _delegateFlags.didMoveToOffset = [_delegate respondsToSelector:@selector(groupView:didMoveToOffset:)];
    _delegateFlags.willOpen = [_delegate respondsToSelector:@selector(groupViewWillOpen:)];
    _delegateFlags.didOpen = [_delegate respondsToSelector:@selector(groupViewDidOpen:)];
    _delegateFlags.willClose = [_delegate respondsToSelector:@selector(groupViewWillClose:)];
    _delegateFlags.didClose = [_delegate respondsToSelector:@selector(groupViewDidClose:)];
}

#pragma mark - Layout
- (void)didMoveToSuperview
{
    if (!self.superview) {
        return;
    }
    [self _configureSubappViews];
    [self layoutSubviews];

    [self _addGestureRecognizers];

    self.alpha = 1.f;
}

- (void)_configureSubappViews
{
    if (_group.state == STKGroupStateEmpty) {
        return;
    }
    [self _reallyConfigureSubappViews];
}

- (void)_reallyConfigureSubappViews
{
    [self resetLayouts];

    _subappLayout = [[STKGroupLayout alloc] init];
    [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
        Class viewClass = [icon iconViewClassForLocation:SBIconLocationHomeScreen];
        SBIconView *iconView = [[[viewClass alloc] initWithDefaultSize] autorelease];
        iconView.frame = (CGRect){CGPointZero, iconView.frame.size};
        iconView.icon = icon;
        iconView.delegate = self.delegate;
        [_subappLayout addIcon:iconView toIconsAtPosition:pos];
        [self _setAlpha:0.f forBadgeAndLabelOfIconView:iconView];
        [self addSubview:iconView];
    }];
    [self _resetDisplacedIconLayout];
}

- (void)_resetDisplacedIconLayout
{
    [_displacedIconLayout release];
    _displacedIconLayout = nil;
    if ([_centralIconView isInDock]) {
        CGSize defaultSize = [CLASS(SBIconView) defaultIconSize];
        SBIconListView *currentListView = [[CLASS(SBIconController) sharedInstance] currentRootIconList];
        _displacedIconLayout = [[STKGroupLayoutHandler layoutForIconsToHideAboveDockedIcon:_group.centralIcon
            usingLayout:_group.layout
            targetFrameProvider:^CGRect(NSUInteger idx) {
                STKGroupSlot slot = (STKGroupSlot){STKPositionTop, idx};
                CGPoint targetPosition = [self _targetPositionForSubappSlot:slot];
                CGPoint targetOrigin = (CGPoint){(targetPosition.x - (defaultSize.width * 0.5f)), (targetPosition.y - (defaultSize.height * 0.5f))};
                CGRect frame = (CGRect){targetOrigin, defaultSize};
                return [self convertRect:frame toView:currentListView];
            }] retain];
    }
    else {
        _displacedIconLayout = [[STKGroupLayoutHandler layoutForIconsToDisplaceAroundIcon:_group.centralIcon usingLayout:_group.layout] retain];
    }
}

#pragma mark - Gesture Handling
- (void)_addGestureRecognizers
{
    [self _removeGestureRecognizers];

    _panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panned:)];
    _panRecognizer.delegate = self;   
    
    _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_doubleTapped:)];
    _tapRecognizer.numberOfTapsRequired = 2;
    _tapRecognizer.delegate = self;

    [_centralIconView addGestureRecognizer:_panRecognizer];
    [_centralIconView addGestureRecognizer:_tapRecognizer];
}

- (void)_removeGestureRecognizers
{
    _panRecognizer.delegate = nil;
    _tapRecognizer.delegate = nil;

    [_panRecognizer.view removeGestureRecognizer:_panRecognizer];
    [_tapRecognizer.view removeGestureRecognizer:_tapRecognizer];

    [_panRecognizer release];
    [_tapRecognizer release];
    _panRecognizer = nil;
    _tapRecognizer = nil;
}

- (void)_panned:(UIPanGestureRecognizer *)recognizer
{
    CGPoint translation = [recognizer translationInView:self];
    double distance = translation.y;
    CGFloat realOffset = (distance / _targetDistance);
    CFTimeInterval offset = (distance / (_targetDistance + kBandingAllowance));
    // `offset` adds banding allowance

    BOOL passedStartPoint = ((realOffset < 0 && _recognizerDirection == STKRecognizerDirectionDown)
                            || (realOffset > 0 && _recognizerDirection == STKRecognizerDirectionUp));

    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            _ignoreRecognizer = NO;
            BOOL isHorizontalSwipe = !((fabsf(translation.x / translation.y) < 5.0) || translation.x == 0);
            if ((self.delegate && ![self.delegate shouldGroupViewOpen:self]) || isHorizontalSwipe) {
                _ignoreRecognizer = YES;
                break;
            }
            if (_delegateFlags.willOpen) {
                [self.delegate groupViewWillOpen:self];
            }
            if (_group.empty || !_subappLayout) {
                [self _reallyConfigureSubappViews];
            }
            _targetDistance = [self _updatedTargetDistance];
            _keyframeDuration = KEYFRAME_DURATION();
            _recognizerDirection = ((translation.y < 0) ? STKRecognizerDirectionUp : STKRecognizerDirectionDown);    
            if ([_centralIconView isInDock]) {
                [self _resetDisplacedIconLayout];
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (_ignoreRecognizer) {
                break;
            }
            if (passedStartPoint) {
                offset = realOffset = 0.f;
            }
            else {
                offset = MIN(fabsf(offset), (_keyframeDuration - 0.00001));
                realOffset = MIN(fabsf(realOffset), 1.0f);
            }
            [self _moveAllIconsToOffset:offset performingBlockOnSubApps:^(SBIconView *iconView) {
                [self _setAlpha:realOffset forBadgeAndLabelOfIconView:iconView];
            }];
            if (_delegateFlags.didMoveToOffset) {
                [_delegate groupView:self didMoveToOffset:realOffset];
            }
            [self _setAlphaForOtherIcons:(1.2 - realOffset)];
            if ([_centralIconView isInDock]) {
                [self _setAlphaForDisplacedIcons:(1.0 - realOffset)];   
            }
            break;
        }
        case UIGestureRecognizerStateEnded: {
            if (!_ignoreRecognizer) {
                CGPoint velocity = [recognizer velocityInView:self];
                if (((_recognizerDirection == STKRecognizerDirectionUp && velocity.y < 0) 
                    || (_recognizerDirection == STKRecognizerDirectionDown && velocity.y > 0))
                    && !passedStartPoint) {
                    [self _animateOpenWithCompletion:nil];
                }
                else {
                    [self _animateClosedWithCompletion:nil];
                }
            }
            _ignoreRecognizer = NO;
            _keyframeDuration = 0.f;
            _targetDistance = 0.f;
            break;
        }
        default: {
            // do nothing
        }
    }
}

- (void)_doubleTapped:(UITapGestureRecognizer *)recog
{
    [self open];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer
{
    BOOL shouldReceive = YES;
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    if ([controller isEditing] || ([controller grabbedIcon] == _group.centralIcon)) {
        shouldReceive = NO;
    }
    else if ([recognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        shouldReceive = (_activationMode == STKActivationModeDoubleTap);
    }
    return shouldReceive;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recog shouldReceiveTouch:(UITouch *)touch
{
    return (([recog isKindOfClass:[UITapGestureRecognizer class]] && _activationMode == STKActivationModeDoubleTap)
           || ([recog isKindOfClass:[UIPanGestureRecognizer class]] && _activationMode != STKActivationModeDoubleTap));
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)ogr
{
    return [self.delegate groupView:self shouldRecognizeGesturesSimultaneouslyWithGestureRecognizer:ogr]; 
}

#pragma mark - Moving
- (void)_moveAllIconsToOffset:(CFTimeInterval)timeOffset performingBlockOnSubApps:(void(^)(SBIconView *))block
{
    void(^mover)(SBIconView *, STKLayoutPosition, NSArray *, NSUInteger, BOOL, CGPoint) = 
    ^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL isSubapp, CGPoint target) {
        if (!iconView) {
            return;
        }
        UIBezierPath *path = [self _cachedPathForIcon:iconView.icon];
        if (!path) {
            target = [self _pointByApplyingBandingToPoint:target withPosition:position];
            path = [self _pathForIconToPoint:target fromIconView:iconView isSubapp:isSubapp];
            [self _cachePath:path forIcon:iconView.icon];
        }
        CAKeyframeAnimation *animation = [self _defaultAnimation];
        animation.path = path.CGPath;
        animation.timeOffset = timeOffset;
        [iconView.layer addAnimation:animation forKey:@"ApexIconMoveAnimation"];
        iconView.layer.position = [iconView.layer.presentationLayer position];
    };

    [_subappLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iv, STKLayoutPosition pos, NSArray *c, NSUInteger i, BOOL *s) {
        if (block) {
            block(iv);
        }
        CGPoint target = [self _targetPositionForSubappSlot:(STKGroupSlot){pos, i}];
        mover(iv, pos, c, i, YES, target);
    }];
    [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger i, BOOL *s) {
        SBIconView *iv = [self _iconViewForIcon:icon];
        if (![_centralIconView isInDock]) {
            CGPoint target = [self _displacedOriginForIcon:iv.icon withPosition:pos];
            mover(iv, pos, c, i, NO, target);
        }
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

- (UIBezierPath *)_pathForIconToPoint:(CGPoint)destination fromIconView:(SBIconView *)iconView isSubapp:(BOOL)isSubapp
{
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGPoint startPoint;    
    if (isSubapp) {
        startPoint = [iconView _iconImageView].layer.position;
    }
    else {
        startPoint = iconView.layer.position;
    }
    [path moveToPoint:startPoint];
    [path addLineToPoint:destination];
    return path;
}

#pragma mark - Animate
- (void)_animateOpenWithCompletion:(void(^)(void))completion
{
    if (_isAnimating) {
        return;
    }
    _isAnimating = YES;
    _isOpen = YES;
    if ([self.delegate respondsToSelector:@selector(groupViewWillOpen:)]) {
        [self.delegate groupViewWillOpen:self];
    }
    [UIView animateWithDuration:0.25f delay:0.0 options:UIViewAnimationOptionCurveEaseOut
        animations:^{
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
                        // However, the path is at target+banding allowance, so subtract that
                        dest = [self _pointByRemovingBandingFromPoint:dest withPosition:pos];
                    }
                    else {
                        // The path is nil, meaning the icons haven't been moved yet, so we can use manual calculation
                        dest = [self _targetPositionForSubappSlot:(STKGroupSlot){pos, idx}];;
                    }
                    dest;
                });
                [self _setAlpha:1.f forBadgeAndLabelOfIconView:iconView];
                [UIView performWithoutAnimation:^{
                    iconView.layer.position = [iconView.layer.presentationLayer position];
                }];
                iconView.layer.position = destination;
                [iconView.layer removeAnimationForKey:@"ApexIconMoveAnimation"];
            }    
        ];
        [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:
            ^(SBIcon *icon, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                SBIconView *iconView = [listView viewForIcon:icon];
                if ([_centralIconView isInDock]) {
                    iconView.alpha = 0.f;   
                }
                else {
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
                    [UIView performWithoutAnimation:^{
                        iconView.layer.position = [iconView.layer.presentationLayer position];
                    }];
                    iconView.layer.position = destination;
                }
                [iconView.layer removeAnimationForKey:@"ApexIconMoveAnimation"];
            }
        ];
        if (_delegateFlags.didMoveToOffset) {
            [_delegate groupView:self didMoveToOffset:1.f];
        }
    } completion:^(BOOL finished) {
        if (finished) {
            if (completion) {
                completion();
            }
            _isAnimating = NO;
            if ([self.delegate respondsToSelector:@selector(groupViewDidOpen:)]) {
                [self.delegate groupViewDidOpen:self];
            }
        }
    }];
}

- (void)_animateClosedWithCompletion:(void(^)(void))completion
{
    if (_isAnimating) {
        return;
    }
    _isAnimating = YES;
    _isOpen = NO;
    if ([self.delegate respondsToSelector:@selector(groupViewWillClose:)]) {
        [self.delegate groupViewWillClose:self];
    }
    [UIView animateWithDuration:0.25f delay:0.0 options:UIViewAnimationOptionCurveEaseOut
        animations:^{
        [self _setAlphaForOtherIcons:1.f];
        [_subappLayout enumerateIconsUsingBlockWithIndexes:
            ^(SBIconView *iconView, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                [self _setAlpha:0.f forBadgeAndLabelOfIconView:iconView];
                [UIView performWithoutAnimation:^{
                    iconView.layer.position = [iconView.layer.presentationLayer position];
                }];
                iconView.frame = (CGRect){CGPointZero, iconView.frame.size};
                [iconView.layer removeAnimationForKey:@"ApexIconMoveAnimation"];
            }    
        ];
        [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:
            ^(SBIcon *icon, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                SBIconView *iconView = [self _iconViewForIcon:icon];
                if ([_centralIconView isInDock]) {
                    iconView.alpha = 1.f;
                }
                [UIView performWithoutAnimation:^{
                    iconView.layer.position = [iconView.layer.presentationLayer position];
                }];
                [iconView.layer removeAnimationForKey:@"ApexIconMoveAnimation"];
            }
        ];
        SBIconListView *listView = STKListViewForIcon(_centralIconView.icon);
        [listView setIconsNeedLayout];

        [listView layoutIconsIfNeeded:0.0f domino:0.f];
        if (_delegateFlags.didMoveToOffset) {
            [_delegate groupView:self didMoveToOffset:0.f];
        }
    } completion:^(BOOL finished) {
        if (finished) {
            if (completion) {
                completion();
            }
            _isAnimating = NO;
            if (_group.empty) {
                [self resetLayouts];
            }
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
    CGPoint target = _centralIconView._iconImageView.layer.position;
    CGSize iconSize = [CLASS(SBIconView) defaultIconSize];
    SBIconListView *listView = STKListViewForIcon(_group.centralIcon);
    if (slot.position == STKPositionTop || slot.position == STKPositionBottom) {
        target.y += ([listView stk_realVerticalIconPadding] + iconSize.height) * factor;
    }
    else if (slot.position == STKPositionLeft || slot.position == STKPositionRight) {
        target.x += ([listView stk_realHorizontalIconPadding] + iconSize.width) * factor;
    }
    if ([_centralIconView isInDock]) {
        SBDockIconListView *dock = (SBDockIconListView *)STKListViewForIcon(_centralIconView.icon);
        target.y -= (dock.frame.origin.y + ([CLASS(SBIconView) defaultIconImageSize].height * 0.5f) - 10.f);
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
        if ((icon == _group.centralIcon) || ([_centralIconView isInDock] &&[ _displacedIconLayout[STKPositionTop] containsObject:icon])) {
            return;
        }
        SBIconView *view = [listView viewForIcon:icon];
        view.alpha = alpha;
        [self _setAlpha:alpha forBadgeAndLabelOfIconView:[listView viewForIcon:icon]];
    };
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    SBIconListView *currentListView = [controller currentRootIconList];
    SBIconListView *dock = [controller dockListView];
    for (SBIcon *icon in [currentListView icons]) {
        setter(currentListView, icon);
    }
    for (SBIcon *icon in [dock icons]) {
        setter(dock, icon);
    }
}

- (void)_setAlpha:(CGFloat)alpha forBadgeAndLabelOfIconView:(SBIconView *)iconView
{
    UIView *view = [iconView valueForKey:@"_labelView"];
    iconView.iconAccessoryAlpha = alpha;
    view.alpha = alpha;
}

- (void)_setAlphaForDisplacedIcons:(CGFloat)alpha
{
    for (SBIcon *icon in _displacedIconLayout) {
        [self _iconViewForIcon:icon].alpha = alpha;
    }
}

- (SBIconView *)_iconViewForIcon:(SBIcon *)icon
{
    return [[CLASS(SBIconViewMap) homescreenMap] mappedIconViewForIcon:icon];
}

- (CGFloat)_updatedTargetDistance
{
    CGFloat defaultHeight = [objc_getClass("SBIconView") defaultIconSize].height;
    CGFloat verticalPadding = [STKListViewForIcon(_group.centralIcon) stk_realVerticalIconPadding];
    return verticalPadding + defaultHeight;
}

#pragma mark - Group Observer
- (void)groupDidRelayout:(STKGroup *)group
{
    [self resetLayouts];
}

- (void)group:(STKGroup *)group replacedIcon:(SBIcon *)replacedIcon inSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon
{
    SBIconView *iconView = (SBIconView *)_subappLayout[slot.position][slot.index];
    [iconView setIcon:icon];
    if (group.hasPlaceholders && [icon isLeafIcon]) {
        [iconView showApexOverlayOfType:STKOverlayTypeEditing];
    }
}

- (void)groupDidAddPlaceholders:(STKGroupView *)groupView
{
    [UIView animateWithDuration:0.15 animations:^{
        [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
            if ([icon isPlaceholder]) {
                Class viewClass = [icon iconViewClassForLocation:SBIconLocationHomeScreen];
                SBIconView *iconView = [[[viewClass alloc] initWithDefaultSize] autorelease];
                iconView.frame = (CGRect){CGPointZero, iconView.frame.size};
                iconView.layer.position = [self _targetPositionForSubappSlot:(STKGroupSlot){pos, idx}];
                iconView.icon = icon;
                iconView.delegate = self.delegate;
                [_subappLayout addIcon:iconView toIconsAtPosition:pos];
                [self _setAlpha:0.f forBadgeAndLabelOfIconView:iconView];
                [self addSubview:iconView];
            }
            else if ([icon isLeafIcon]) {
                SBIconView *iconView = _subappLayout[pos][idx];
                [iconView showApexOverlayOfType:STKOverlayTypeEditing];
            }
        }];
        [self _hideIconsForPlaceholders];
    }];
}

- (void)groupWillRemovePlaceholders:(STKGroup *)group
{
    NSMutableArray *viewsToRemove = [NSMutableArray array];
    [UIView animateWithDuration:0.15 animations:^{
        [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
            // we cannot mutate _subappLayout during iteration, so iterate over _group.layout
            // and store the views to be removed in a separate array
            SBIconView *iconView = _subappLayout[pos][idx];
            if ([icon isPlaceholder]) {
                [iconView.superview sendSubviewToBack:iconView];
                iconView.frame = (CGRect){CGPointZero, iconView.frame.size};
                [viewsToRemove addObject:iconView];
            }
            else if ([iconView.icon isLeafIcon]) {
                [iconView removeApexOverlay];
            }
        }];
        [self _unhideIconsForPlaceholders];
    } completion:^(BOOL finished) {
        for (SBIconView *view in viewsToRemove) {
            [view removeFromSuperview];
            [_subappLayout removeIcon:view fromIconsAtPosition:[_subappLayout slotForIcon:view].position];
        }
    }];
}

- (void)groupDidFinalizeState:(STKGroup *)group
{
    [self resetLayouts];
}

- (void)_hideIconsForPlaceholders
{
    _iconsHiddenForPlaceholders = [[NSMutableSet alloc] initWithCapacity:4];
    SBIconListView *listView = [[CLASS(SBIconController) sharedInstance] currentRootIconList];
    for (SBIconView *iconView in _subappLayout) {
        if (![iconView.icon isPlaceholder]) {
            continue;
        }
        CGRect frame = [iconView.superview convertRect:iconView.frame toView:listView];
        for (SBIcon *icon in [listView icons]) {
            SBIconView *otherView = [listView viewForIcon:icon];
            if ((otherView != _centralIconView) && (otherView != iconView) && (CGRectIntersectsRect(frame, otherView.frame))) {
                [(NSMutableSet *)_iconsHiddenForPlaceholders addObject:otherView];
                otherView.alpha = 0.f;
                break;
            }
        }
    }
}

- (void)_unhideIconsForPlaceholders
{
    for (SBIconView *iconView in _iconsHiddenForPlaceholders) {
        iconView.alpha = 0.2f;
    }
    [_iconsHiddenForPlaceholders release];
    _iconsHiddenForPlaceholders = nil;
}

@end
