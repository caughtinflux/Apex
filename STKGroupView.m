#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "STKGroupView.h"
#import "STKConstants.h"

#undef CLASS
#define CLASS(cls) NSClassFromString(@#cls)

#define kBandingAllowance        2000.f
#define kDockedBandingAllowance  20.f

#define kPopoutDistance          12.f
#define kCentralIconPreviewScale 0.95f
#define kSubappPreviewScale      0.66f

#define kGrabberDistanceFromEdge -2.f
#define kGrabberHeight           5.f

#define CURRENTLY_SHOWS_PREVIEW (!_group.empty && _showPreview)
#define SCALE_CENTRAL_ICON (CURRENTLY_SHOWS_PREVIEW || (_topGrabberView && _bottomGrabberView))

#define kDefaultAnimationOptions (UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState)

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

    UIView *_topGrabberView;
    UIView *_bottomGrabberView;
    CGRect _topGrabberOriginalFrame;
    CGRect _bottomGrabberOriginalFrame;

    BOOL _isOpen;
    BOOL _isAnimatingOpen;
    BOOL _isAnimatingClosed;
    BOOL _ignoreRecognizer;
    BOOL _hasVerticalIcons;
    BOOL _isUpwardSwipe;
    CGFloat _lastDistanceFromCenter;
    CGFloat _targetDistance;
    CGFloat _distanceRatio;
    CGFloat _currentBandingAllowance;
    STKRecognizerDirection _recognizerDirection;

    struct {
        NSUInteger didMoveToOffset:1;
        NSUInteger shouldOpen:1;
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
        _centralIconView = [[CLASS(SBIconViewMap) homescreenMap] iconViewForIcon:_group.centralIcon];
    }
    return self;
}

- (void)dealloc
{
    if ([self.delegate respondsToSelector:@selector(groupViewWillBeDestroyed:)]) {
        [self.delegate groupViewWillBeDestroyed:self];
    }
    [self resetLayouts];
    [self _removeGestureRecognizers];
    self.group = nil;
    [super dealloc];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if ([_centralIconView pointInside:[self convertPoint:point toView:_centralIconView] withEvent:event]) {
        return _centralIconView;
    }
    for (SBIconView *iconView in _subappLayout) {
        if ([iconView pointInside:[self convertPoint:point toView:iconView] withEvent:event]) {
            return iconView;
        }
    }
    return nil;
}

#pragma mark - Public Methods
- (void)open
{
    [self _animateOpenWithCompletion:nil];
}

- (void)openWithCompletionHandler:(void(^)(void))completion
{
    [self _animateOpenWithCompletion:completion];
}

- (void)close
{
    [self _animateClosedWithCompletion:nil];
}

- (void)closeWithCompletionHandler:(void(^)(void))completion
{
    [self _animateClosedWithCompletion:completion];
}

- (void)resetLayouts
{
    if (_isAnimatingOpen || _isAnimatingClosed) {
        return;
    }
    if (_subappLayout) {
        [_centralIconView stk_setImageViewScale:1.f];
    }
    BOOL didShowGrabbers = self.showGrabbers;
    self.showGrabbers = NO;
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];   
    [_subappLayout release];
    _subappLayout = nil;
    [_displacedIconLayout release];
    _displacedIconLayout = nil;
    self.showGrabbers = didShowGrabbers;
    [self _configureSubappViews];
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

    _centralIconView.delegate = [CLASS(SBIconController) sharedInstance];

    _group = [group retain];
    [_group addObserver:self];

    _centralIconView = [[CLASS(SBIconViewMap) homescreenMap] iconViewForIcon:_group.centralIcon];
    _centralIconView.delegate = self.delegate;

    [self resetLayouts];
}

- (void)setShowPreview:(BOOL)shouldShow
{
    _showPreview = shouldShow;
    if (!_isOpen) [self resetLayouts];
}

- (void)setShowGrabbers:(BOOL)show
{
    if (show && (_showPreview == NO) && (_group.state != STKGroupStateEmpty)) {
        [self _addGrabbers];
        [_centralIconView stk_setImageViewScale:kCentralIconPreviewScale];
    }
    else {
        [self _removeGrabbers];
        [_centralIconView stk_setImageViewScale:1.0f];
    }
    _showGrabbers = show;
}

- (void)setDelegate:(id<STKGroupViewDelegate>)delegate
{
    _delegate = delegate;
    _delegateFlags.didMoveToOffset = [self.delegate respondsToSelector:@selector(groupView:didMoveToOffset:)];
    _delegateFlags.shouldOpen = [self.delegate respondsToSelector:@selector(shouldGroupViewOpen:)];
    _delegateFlags.willOpen = [self.delegate respondsToSelector:@selector(groupViewWillOpen:)];
    _delegateFlags.didOpen = [self.delegate respondsToSelector:@selector(groupViewDidOpen:)];
    _delegateFlags.willClose = [self.delegate respondsToSelector:@selector(groupViewWillClose:)];
    _delegateFlags.didClose = [self.delegate respondsToSelector:@selector(groupViewDidClose:)];
    _centralIconView = [[CLASS(SBIconViewMap) homescreenMap] iconViewForIcon:_group.centralIcon];
    _centralIconView.delegate = _delegate;
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
    if (!CURRENTLY_SHOWS_PREVIEW) {
        return;
    }
    [self _reallyConfigureSubappViews];
}

- (void)_reallyConfigureSubappViews
{
    [_subappLayout release];

    _subappLayout = [[STKGroupLayout alloc] init];

    [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
        Class viewClass = [icon iconViewClassForLocation:SBIconLocationHomeScreen];
        SBIconView *iconView = [[[viewClass alloc] initWithDefaultSize] autorelease];
        iconView.frame = _centralIconView.bounds;
        iconView.icon = icon;
        iconView.delegate = self.delegate;
        [_subappLayout addIcon:iconView toIconsAtPosition:pos];
        [self _setAlpha:0.f forBadgeAndLabelOfIconView:iconView];
        [self addSubview:iconView];
    }];

    [self _resetDisplacedIconLayout];

    if (SCALE_CENTRAL_ICON) {
        [self _setupPreview];
        [_centralIconView stk_setImageViewScale:kCentralIconPreviewScale];
    }
}

- (void)_setupPreview
{
    [_subappLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx, BOOL *stop) {
        CGRect frame = _centralIconView.bounds;
        CGPoint newOrigin = frame.origin;
        // Check if it's the last object, only if not empty
        if (CURRENTLY_SHOWS_PREVIEW && idx == currentArray.count - 1) {
            CGFloat *memberToModify = (STKPositionIsVertical(position) ? &newOrigin.y : &newOrigin.x);
            CGFloat negator = (position == STKPositionTop || position == STKPositionLeft ? -1 : 1);
            *memberToModify += kPopoutDistance * negator;
        }
        frame.origin = newOrigin; 
        iconView.frame = frame;
        if (![iconView.icon isLeafIcon] && _group.state != STKGroupStateEmpty) {
            iconView.alpha = 0.f;
        }
        // Hide the label and badge
        [self _setAlpha:0.f forBadgeAndLabelOfIconView:iconView];
        if (SCALE_CENTRAL_ICON) {
            // Scale the icon back down to the smaller size
            [iconView stk_setImageViewScale:kSubappPreviewScale];
        }
    }];
}

- (void)_addGrabbers
{
    CGRect iconImageFrame = [_centralIconView iconImageFrame];
    CGFloat grabberWidth = (floorf(iconImageFrame.size.width * 0.419354839) + 1.f);

    _topGrabberView = [[UIView new] autorelease];
    _topGrabberView.frame = (CGRect){{0, self.bounds.origin.y - kGrabberDistanceFromEdge - kGrabberHeight + 2.f}, {grabberWidth, kGrabberHeight}};
    _topGrabberView.center = (CGPoint){[_centralIconView iconImageCenter].x, _topGrabberView.center.y};

    _bottomGrabberView = ([_centralIconView isInDock] ? nil : [[UIView new] autorelease]);
    _bottomGrabberView.frame = (CGRect){{0, iconImageFrame.size.height + kGrabberDistanceFromEdge - 4.f}, {grabberWidth, kGrabberHeight}};
    _bottomGrabberView.center = (CGPoint){[_centralIconView iconImageCenter].x, _bottomGrabberView.center.y};

    _topGrabberView.layer.cornerRadius = _bottomGrabberView.layer.cornerRadius = (kGrabberHeight * 0.5f);
    _topGrabberView.layer.masksToBounds = _bottomGrabberView.layer.masksToBounds = YES;
    _topGrabberView.backgroundColor = _bottomGrabberView.backgroundColor = [UIColor colorWithWhite:1.f alpha:0.6f];

    _topGrabberOriginalFrame = _topGrabberView.frame;
    _bottomGrabberOriginalFrame = _bottomGrabberView.frame;
    [self addSubview:_topGrabberView];
    [self addSubview:_bottomGrabberView];
}

- (void)_removeGrabbers
{
    [_topGrabberView removeFromSuperview];
    [_bottomGrabberView removeFromSuperview];
    _topGrabberView = nil;
    _bottomGrabberView = nil;
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
                CGRect frame = (CGRect){[self _targetOriginForSubappSlot:slot], defaultSize};
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

#pragma mark - Activation Recognizer Handling
#define kBandingFactor  0.25 // The factor by which the distance should be multiplied to simulate the rubber banding effect
- (void)_panned:(UIPanGestureRecognizer *)sender
{
    if (self.isOpen) {
        _ignoreRecognizer = YES;
        return;
    }
    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
            CGPoint translation = [sender translationInView:self];
            _isUpwardSwipe = ([sender velocityInView:self].y < 0);
            
            BOOL isHorizontalSwipe = !((fabsf(translation.x / translation.y) < 5.0) || translation.x == 0);
            BOOL isUpwardSwipeInSwipeDownMode = (_activationMode == STKActivationModeSwipeDown && _isUpwardSwipe);
            BOOL isDownwardSwipeInSwipeUpMode = (_activationMode == STKActivationModeSwipeUp && (_isUpwardSwipe == NO));
            BOOL delegateDeniedOpen = (self.delegate && ![self.delegate shouldGroupViewOpen:self]);
            if (delegateDeniedOpen || isHorizontalSwipe || isUpwardSwipeInSwipeDownMode || isDownwardSwipeInSwipeUpMode) {
                _ignoreRecognizer = YES;
                return;
            }
            if (_delegateFlags.willOpen) {
                [self.delegate groupViewWillOpen:self];
            }
            if (!CURRENTLY_SHOWS_PREVIEW || !_subappLayout) {
                [self _reallyConfigureSubappViews];
            }
            [self _updateTargetDistance];
            [self _calculateDistanceRatio];
            _recognizerDirection = ((translation.y < 0) ? STKRecognizerDirectionUp : STKRecognizerDirectionDown);
            _hasVerticalIcons = ([_subappLayout[STKPositionTop] count] > 0) || ([_subappLayout[STKPositionBottom] count] > 0);
            _targetDistance *= (_hasVerticalIcons == NO ? _distanceRatio : 1.f);
            _lastDistanceFromCenter = 0.f;
            _currentBandingAllowance = ([_centralIconView isInDock] ? kDockedBandingAllowance : kBandingAllowance);
            
            [self _resetDisplacedIconLayout];
            [self _performScaleAnimationOnCentralIconFromScale:1.1f toScale:1.f];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (_ignoreRecognizer) {
                return;
            }
            CGFloat change = [sender translationInView:self].y;
            if (_isUpwardSwipe) {
                change = -change;
            }
            if ((change > 0) && (_lastDistanceFromCenter >= _targetDistance)) {
                // Factor this down to simulate elasticity when the icons have reached their target locations
                // The stack allows the icons to go beyond their targets for a little distance
                change *= kBandingFactor;
            }

            CGFloat offset = fminf((_lastDistanceFromCenter / _targetDistance), 1.f);
            [self _setAlphaForOtherIcons:(1.2 - offset)];
            if ([_centralIconView isInDock]) {
                [self _setAlphaForDisplacedIcons:(1.0 - offset)];   
            }
            [self _moveByDistance:change performingBlockOnSubApps:^(SBIconView *subappView, STKGroupSlot slot) {
                [self _adjustScaleAndTransparencyOfSubapp:subappView inSlot:slot forOffset:offset];
            }];
            if (_delegateFlags.didMoveToOffset) {
                [self.delegate groupView:self didMoveToOffset:offset];
            }
            [sender setTranslation:CGPointZero inView:self];
            break;
        }
        default: {
            if (!_ignoreRecognizer) {
                CGPoint velocity = [sender velocityInView:self];
                if (   (_recognizerDirection == STKRecognizerDirectionUp   && velocity.y < 0)
                    || (_recognizerDirection == STKRecognizerDirectionDown && velocity.y > 0)
                    || (_lastDistanceFromCenter >= 25.f)) {
                    [self _animateOpenWithCompletion:nil];
                }
                else {
                    [self _animateClosedWithCompletion:nil];
                }
            }
            _ignoreRecognizer = NO; 
            _isUpwardSwipe = NO; 
            _hasVerticalIcons = NO;
            _targetDistance = 0.f;
            _recognizerDirection = STKRecognizerDirectionNone;
            break;
        }
    }
}

- (void)_adjustScaleAndTransparencyOfSubapp:(SBIconView *)subappView inSlot:(STKGroupSlot)slot forOffset:(CGFloat)offset 
{
    CGFloat midWayDistance = (_targetDistance * 0.5f);
    [self _setAlpha:offset forBadgeAndLabelOfIconView:subappView];
    if (slot.index == 0) {
        if (_hasVerticalIcons && STKPositionIsVertical(slot.position)) {
            _lastDistanceFromCenter = fabsf(subappView.frame.origin.y - _centralIconView.bounds.origin.y);
        }
        else if (!_hasVerticalIcons && STKPositionIsHorizontal(slot.position)) {
           _lastDistanceFromCenter = fabsf(subappView.frame.origin.x - _centralIconView.bounds.origin.x);
        }
    }
    if (SCALE_CENTRAL_ICON) { 
        if (_lastDistanceFromCenter <= midWayDistance) {
            // If the icons are past the halfway mark, start increasing/decreasing their scale.
            CGFloat stackIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kSubappPreviewScale);
            [subappView stk_setImageViewScale:stackIconTransformScale];
            CGFloat centralIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kCentralIconPreviewScale);
            [_centralIconView stk_setImageViewScale:centralIconTransformScale];
        }
        else {      
            [_centralIconView stk_setImageViewScale:1.f];
            [subappView stk_setImageViewScale:1.f];
        }
    }
}

- (void)_doubleTapped:(UITapGestureRecognizer *)recog
{
    if (!self.delegate || [self.delegate shouldGroupViewOpen:self]) {
        [self open];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer
{
    BOOL shouldBegin = YES;
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    if ([controller isEditing] || ([controller grabbedIcon] == _group.centralIcon)) {
        shouldBegin = NO;
    }
    else if ([recognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        shouldBegin = (_activationMode == STKActivationModeDoubleTap);
        if (_delegateFlags.shouldOpen) {
            shouldBegin = (shouldBegin && [self.delegate shouldGroupViewOpen:self]);
        }
    }
    return shouldBegin;
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
// These macros give us information about _a relative to _b, relative to their paths.
#define IS_GREATER(_float_a, _float_b, _position) ((_position == STKPositionTop || _position == STKPositionLeft) ? (_float_a < _float_b) : (_float_a > _float_b))
#define IS_LESSER(_float_a, _float_b, _position) ((_position == STKPositionTop || _position == STKPositionLeft) ? (_float_a > _float_b) : (_float_a < _float_b))

- (void)_moveByDistance:(CGFloat)distance performingBlockOnSubApps:(void(^)(SBIconView *iv, STKGroupSlot slot))block
{
    if (![_centralIconView isInDock]) {
        [self _moveDisplacedIconsByDistance:distance];
    }
    [self _moveSubappsByDistance:distance performingTask:block];
    [self _moveGrabbersByDistance:distance];
    if (_delegateFlags.didMoveToOffset) {
        [self.delegate groupView:self didMoveToOffset:fminf((_lastDistanceFromCenter / _targetDistance), 1.f)];   
    }
}

- (void)_moveDisplacedIconsByDistance:(CGFloat)distance
{
    SBIconListView *listView = STKListViewForIcon(_centralIconView.icon);
    [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:
        ^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL *stop) {
            SBIconView *iconView = [self _iconViewForIcon:icon]; // Get the on-screen icon view from the list view.
            CGRect iconFrame = iconView.frame;
            CGRect newFrame = iconView.frame;
            CGPoint originalOrigin = [listView originForIcon:icon];
            CGPoint targetOrigin = [self _displacedOriginForIcon:icon withPosition:position];
            NSUInteger appearingIconsCount = [_subappLayout[position] count];
            CGFloat factoredDistance = (distance * appearingIconsCount);  // Factor the distance up by the number of icons that are coming in at that position
            
            CGFloat *targetCoord, *currentCoord, *newCoord, *originalCoord;
            CGFloat moveDistance;
            if (STKPositionIsVertical(position)) {
                targetCoord = &(targetOrigin.y); 
                currentCoord = &(iconFrame.origin.y);
                newCoord = &(newFrame.origin.y);
                originalCoord = &(originalOrigin.y);
                moveDistance = factoredDistance;
            }
            else {
                targetCoord = &(targetOrigin.x);
                currentCoord = &(iconFrame.origin.x);
                newCoord = &(newFrame.origin.x);
                originalCoord = &(originalOrigin.x);
                // The distance to be moved horizontally is slightly different than vertical, multiply it by the ratio to have them work perfectly. :)
                moveDistance = (factoredDistance * _distanceRatio);
            }
            CGFloat negator = ((position == STKPositionTop || position == STKPositionLeft) ? -1.f : 1.f);
            moveDistance *= negator;
            if (IS_GREATER((*currentCoord + (moveDistance / appearingIconsCount)), *targetCoord, position)) {
                // If, after moving, the icon would pass its target, factor the distance back to it's original.
                // Now it has to move only as much as all the other icons
                moveDistance /= appearingIconsCount;
            }
            *targetCoord += (_currentBandingAllowance * negator);
            if (IS_GREATER(*currentCoord + moveDistance, *targetCoord, position)) {
                // Do not go beyond target
                *newCoord = *targetCoord;
            }
            else if (IS_LESSER(*currentCoord + moveDistance, *originalCoord, position)) {
                // Or beyond the original position on the homescreen
                *newCoord = *originalCoord;
            }
            else {
                // Move that shit
                *newCoord += moveDistance;
            }
            iconView.frame = newFrame;
    }];
}

- (void)_moveSubappsByDistance:(CGFloat)distance performingTask:(void(^)(SBIconView *iv, STKGroupSlot slot))task
{
    BOOL isShowingPreview = CURRENTLY_SHOWS_PREVIEW;
    [_subappLayout enumerateIconsUsingBlockWithIndexes:
        ^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx, BOOL *stop) {
            STKGroupSlot slot = (STKGroupSlot){position, idx};
            if (task) {
                task(iconView, slot);
            }
            CGRect iconFrame = iconView.frame;
            CGRect newFrame = iconView.frame;
            CGPoint targetOrigin = [self _targetOriginForSubappSlot:slot];
            CGRect centralFrame = _centralIconView.bounds;
            CGFloat negator = ((position == STKPositionTop || position == STKPositionLeft) ? -1.f : 1.f);
            CGFloat distanceRatio = 1.f;
            CGFloat *targetCoord, *currentCoord, *newCoord, *centralCoord;
            CGFloat moveDistance = distance * negator;
            if (STKPositionIsVertical(position)) {
                targetCoord = &(targetOrigin.y);
                currentCoord = &(iconFrame.origin.y);
                newCoord = &(newFrame.origin.y);
                centralCoord = &(centralFrame.origin.y);
            }
            else {
                targetCoord = &(targetOrigin.x);
                currentCoord = &(iconFrame.origin.x);
                newCoord = &(newFrame.origin.x);
                centralCoord = &(centralFrame.origin.x);
                distanceRatio = _distanceRatio;
            }
            CGFloat multFactor = (IS_LESSER((*currentCoord + moveDistance), *targetCoord, position) ? (idx + 1) : 1);
            // Compensate for the popout if necessary
            CGFloat popComp = ((idx == currentArray.count - 1 && isShowingPreview) ? ((*targetCoord - kPopoutDistance * negator) / *targetCoord) : 1.f);
            moveDistance *= (distanceRatio * multFactor * popComp);
            if (IS_GREATER((*currentCoord + (moveDistance / popComp)), *targetCoord, position)) {
                // Don't compensate for anything if the icon is moving past the target
                moveDistance /= popComp;
            }
            // Modify the target to allow for an extra distance specified by _currentBandingAllowance for the rubber banding effect
            *targetCoord += (_currentBandingAllowance * negator);
            if (IS_LESSER((*currentCoord + moveDistance), *centralCoord, position)) {
                // going past start point, don't move further
                newFrame = centralFrame;
            }
            else if (IS_LESSER((*currentCoord + moveDistance), *targetCoord, position)) {
                // we're neither here nor there – just floating through space somewhere in between
                *newCoord += moveDistance;
            }
            else if (IS_GREATER((*currentCoord + moveDistance), *targetCoord, position)) {
                // trying to move past the target! STICK TO THE TARGET, ICONVIEW...STICK TO THE TARGET.
                *newCoord = *targetCoord;
            }
            iconView.frame = newFrame;
    }];
}

- (void)_calculateDistanceRatio
{
    SBIconListView *listView = STKListViewForIcon(_centralIconView.icon);
    CGPoint referencePoint = [listView originForIconAtCoordinate:(SBIconCoordinate){2, 2}];
    CGPoint verticalOrigin = [listView originForIconAtCoordinate:(SBIconCoordinate){1, 2}];
    CGPoint horizontalOrigin = [listView originForIconAtCoordinate:(SBIconCoordinate){2, 1}];
    
    CGFloat verticalDistance = referencePoint.y - verticalOrigin.y;
    CGFloat horizontalDistance = referencePoint.x - horizontalOrigin.x;
    _distanceRatio = (horizontalDistance / verticalDistance);
}

- (void)_moveGrabbersByDistance:(CGFloat)distance
{    
    CGFloat midWayDistance = (_targetDistance * 0.5);
    CGFloat grabberAlpha = STKScaleNumber(_lastDistanceFromCenter, 0, midWayDistance + 10, 1.0, 0.0);
    if ([_subappLayout[STKPositionTop] count] > 0) {
        if ((_topGrabberView.frame.origin.y - distance) < _topGrabberOriginalFrame.origin.y) {
            _topGrabberView.frame = (CGRect){{_topGrabberView.frame.origin.x, _topGrabberView.frame.origin.y - distance},
                                              _topGrabberView.frame.size};
        }
    }
    if ([_subappLayout[STKPositionBottom] count] > 0) {
        if ((_bottomGrabberView.frame.origin.y + distance) > _bottomGrabberOriginalFrame.origin.y) {
            _bottomGrabberView.frame = (CGRect){{_bottomGrabberView.frame.origin.x, _bottomGrabberView.frame.origin.y + distance},
                                                 _bottomGrabberView.frame.size};
        }
    }
    _topGrabberView.alpha = _bottomGrabberView.alpha = grabberAlpha;
}

#pragma mark - Animate
- (void)_animateOpenWithCompletion:(void(^)(void))completion
{
    if (_isAnimatingOpen) {
        return;
    }
    _isAnimatingOpen = YES;
    _isOpen = YES;
    if ([self.delegate respondsToSelector:@selector(groupViewWillOpen:)]) {
        [self.delegate groupViewWillOpen:self];
    }
    if (!_subappLayout) {
        [self _reallyConfigureSubappViews];
    }
    SBIconListView *listView = STKListViewForIcon(_centralIconView.icon);
    void(^animationBlock)(void) = ^{
        [_subappLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
            [self _setAlpha:1.0 forBadgeAndLabelOfIconView:iconView];
            CGPoint origin = [self _targetOriginForSubappSlot:(STKGroupSlot){pos, idx}];
            iconView.frame = (CGRect){origin, iconView.frame.size};
            [iconView stk_setImageViewScale:1.f];
        }];
        [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
            SBIconView *iconView = [listView viewForIcon:icon];
            if ([_centralIconView isInDock]) {
                iconView.alpha = 0.f;
            }
            else {
                CGPoint destination = [self _displacedOriginForIcon:icon withPosition:pos];
                iconView.frame = (CGRect){destination, iconView.frame.size};
            };
        }];
    };

    void(^completionBlock)(BOOL finished) = ^(BOOL finished) {
        if (completion) {
            completion();
        }
        _isAnimatingOpen = NO;
        if ([self.delegate respondsToSelector:@selector(groupViewDidOpen:)]) {
            [self.delegate groupViewDidOpen:self];
        }
    };
    [UIView animateWithDuration:0.8
                          delay:0.0
         usingSpringWithDamping:0.5f
          initialSpringVelocity:0.5f
                        options:kDefaultAnimationOptions
                     animations:animationBlock
                     completion:completionBlock];
    [UIView animateWithDuration:0.25 delay:0.0 options:kDefaultAnimationOptions animations:^{
        if ([_centralIconView isInDock]) {
            for (SBIcon *icon in _displacedIconLayout) {
                [listView viewForIcon:icon].alpha = 0.f;
            }
        }
        [_centralIconView stk_setImageViewScale:1.f];
        [self _setAlphaForOtherIcons:0.2f];
        _topGrabberView.alpha = _bottomGrabberView.alpha = 0.f;
        if (_delegateFlags.didMoveToOffset) {
            [self.delegate groupView:self didMoveToOffset:1.f];
        }
    } completion:nil];
}

- (void)_animateClosedWithCompletion:(void(^)(void))completion
{
    if (_isAnimatingClosed) {
        return;
    }
    _isAnimatingClosed = YES;
    _isOpen = NO;
    if ([self.delegate respondsToSelector:@selector(groupViewWillClose:)]) {
        [self.delegate groupViewWillClose:self];
    }
    for (SBIconView *iconView in _subappLayout) {
        if ([iconView.icon isLeafIcon]) [iconView removeApexOverlay];
    }
    CGFloat scale = ((SCALE_CENTRAL_ICON) ? kCentralIconPreviewScale : 1.f);
    [self _performScaleAnimationOnCentralIconFromScale:(scale - 0.1f) toScale:scale];
    [UIView animateWithDuration:0.25f
        delay:0.0
        options:kDefaultAnimationOptions
        animations:^{
            [self _setAlphaForOtherIcons:1.f];
            [self _setupPreview];

            _topGrabberView.frame = _topGrabberOriginalFrame;
            _bottomGrabberView.frame = _bottomGrabberOriginalFrame;
            _topGrabberView.alpha = _bottomGrabberView.alpha = 1.f;

            [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:
                ^(SBIcon *icon, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                    SBIconView *iconView = [self _iconViewForIcon:icon];
                    if ([_centralIconView isInDock]) {
                        iconView.alpha = 1.f;
                    }
                }
            ];
            
            SBIconListView *listView = STKListViewForIcon(_centralIconView.icon);
            [listView setIconsNeedLayout];
            [listView layoutIconsIfNeeded:0.0f domino:0.f];

            if (_delegateFlags.didMoveToOffset) {
                [self.delegate groupView:self didMoveToOffset:0.f];
            }
        }
        completion:^(BOOL finished) {
            if (completion) {
                completion();
            }
            _isAnimatingClosed = NO;
            if (!CURRENTLY_SHOWS_PREVIEW) {
                [self resetLayouts];
            }
            if ([self.delegate respondsToSelector:@selector(groupViewDidClose:)]) {
                [self.delegate groupViewDidClose:self];
            }
        }
    ];
}

- (void)_performScaleAnimationOnCentralIconFromScale:(CGFloat)fromScale toScale:(CGFloat)toScale
{
    [UIView animateWithDuration:(0.25 * 0.6) delay:0 options:(UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState) animations:^{
        [_centralIconView stk_setImageViewScale:fromScale];
    } completion:^(BOOL done) {
        [UIView animateWithDuration:(0.25 * 0.6) delay:0 options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState) animations:^{
            [_centralIconView stk_setImageViewScale:toScale];
        } completion:nil];
    }];
}

#pragma mark - Coordinate Calculations
- (CGPoint)_targetOriginForSubappSlot:(STKGroupSlot)slot
{
    CGFloat negator = ((slot.position == STKPositionTop || slot.position == STKPositionLeft) ? -1.f : 1.f);
    CGFloat factor = (slot.index + 1) * negator;
    CGPoint target = CGPointZero;
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
        SBRootFolderView *rootView = [[CLASS(SBIconController) sharedInstance] _rootFolderController].contentView;
        SBIconListPageControl *pageControl = [rootView valueForKey:@"_pageControl"];
        target.y -= (pageControl.frame.size.height - (ISPAD() ? 40.f : [dock stk_realVerticalIconPadding]));
    }
    return target;
}

- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position
{
    // Calculate the positions manually
    SBIconListView *listView = STKListViewForIcon(_group.centralIcon);
    SBIconView *iconView = [self _iconViewForIcon:icon];
    STKGroupLayout *layout = _group.layout;
    
    CGPoint originalOrigin = [listView originForIcon:icon];
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
    void(^setter)(id, id) = ^(SBIconListView *listView, SBIcon *icon) {
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

- (void)_updateTargetDistance
{
    _targetDistance = ([self _targetOriginForSubappSlot:(STKGroupSlot){STKPositionTop, 0}].y * -1.f);
}

#pragma mark - Group Observer
- (void)groupDidRelayout:(STKGroup *)group
{
    [self resetLayouts];
}

- (void)group:(STKGroup *)group replacedIcon:(SBIcon *)replacedIcon inSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon
{
    SBIconView *iconView = (SBIconView *)[_subappLayout iconInSlot:slot];
    [iconView setIcon:icon];
    if (group.hasPlaceholders && [icon isLeafIcon]) {
        [iconView showApexOverlayOfType:STKOverlayTypeEditing];
    }
}

- (void)group:(STKGroup *)group removedIcon:(SBIcon *)icon inSlot:(STKGroupSlot)slot
{
    SBIconView *iconView = (SBIconView *)[_subappLayout iconInSlot:slot];
    [iconView removeFromSuperview];
    [_subappLayout removeIcon:iconView fromIconsAtPosition:slot.position];
}

- (void)groupDidAddPlaceholders:(STKGroupView *)groupView
{
    [UIView animateWithDuration:0.15 animations:^{
        [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
            if ([icon isPlaceholder]) {
                Class viewClass = [icon iconViewClassForLocation:SBIconLocationHomeScreen];
                SBIconView *iconView = [[[viewClass alloc] initWithDefaultSize] autorelease];
                iconView.frame = (CGRect){[self _targetOriginForSubappSlot:(STKGroupSlot){pos, idx}], iconView.frame.size};
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
