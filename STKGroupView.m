#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <UIKit/_UILegibilitySettings.h>
#import <QuartzCore/QuartzCore.h>

#import "SBIconViewMap+ApexAdditions.h"
#import "STKGroupView.h"
#import "STKConstants.h"

#undef CLASS
#define CLASS(cls) NSClassFromString(@#cls)

#define kBandingAllowance        2000.f
#define kDockedBandingAllowance  20.f

#define kPopoutDistance          (ISPAD() ? 15.f : 12.f)
#define kCentralIconPreviewScale 0.95f
#define kSubappPreviewScale      0.66f
#define kSubappPreviewAlpha      0.88f

#define kGrabberDistanceFromEdge -2.f
#define kGrabberHeight           6.f
#define kGrabberLightColour      [UIColor colorWithWhite:1.f alpha:0.44f]
#define kGrabberDarkColour       [UIColor colorWithWhite:0.f alpha:0.44f]

#define kBackgroundFadeAlpha     0.2f

#define CURRENTLY_SHOWS_PREVIEW (!_group.empty && _showPreview)
#define SCALE_CENTRAL_ICON (CURRENTLY_SHOWS_PREVIEW || (_showGrabbers && !_group.empty))

#define kDefaultAnimationOptions (UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction)
#define kOpenAnimationFadeDuration 0.25
#define kOpenAnimationDamping      0.5
#define kOpenAnimationVelocity     0.5
#define kCloseAnimationDuration    0.25
#define kPlaceholderAddDamping     0.4
#define kPlaceholderAddVelocity    0.5
#define kPlaceholderRemoveDuration 0.15

static CGFloat kOpenAnimationDuration;
static CGFloat kPlaceholderAddDuration;

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

+ (void)initialize
{
    kOpenAnimationDuration = 0.8;
    kPlaceholderAddDuration = 0.7;
    if (IS_7_1()) {
        static const CGFloat k7_1_AnimationFactor = 0.5625;
        STKLog(@"Changing durations for iOS 7.1+");
        kOpenAnimationDuration *= k7_1_AnimationFactor;
        kPlaceholderAddDuration *= k7_1_AnimationFactor;
    }
}

- (instancetype)initWithGroup:(STKGroup *)group iconViewSource:(id<STKIconViewSource>)iconViewSource
{
    NSParameterAssert(group);
    NSParameterAssert(iconViewSource);
    if ((self = [super initWithFrame:CGRectZero])) {
        self.iconViewSource = iconViewSource;
        self.group = group;
        self.alpha = 0.f;
    }
    return self;
}

- (void)dealloc
{
    if ([self.delegate respondsToSelector:@selector(groupViewWillBeDestroyed:)]) {
        [self.delegate groupViewWillBeDestroyed:self];
    }
    if (_subappLayout) {
        [_centralIconView stk_setImageViewScale:1.f];
    }
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self _removeGrabbers];
    [self _removeGestureRecognizers];
    [_group removeObserver:self];

    _centralIconView.delegate = [CLASS(SBIconController) sharedInstance];

    [_centralIconView release];
    [_subappLayout release];
    [_displacedIconLayout release];
    [_group release];
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
    _ignoreRecognizer = NO;
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
    STKGroupLayout *subappLayout = _subappLayout;
    _subappLayout = nil;
    [subappLayout release];
    [_displacedIconLayout release];
    _displacedIconLayout = nil;
    [self _configureSubappViews];
    self.showGrabbers = didShowGrabbers;
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

- (void)resetImageViewScale
{
    if (SCALE_CENTRAL_ICON) {
        [_centralIconView stk_setImageViewScale:kCentralIconPreviewScale];
    }
}

- (void)setGroup:(STKGroup *)group
{
    [_group removeObserver:self];
    [_group release];

    _centralIconView.delegate = [CLASS(SBIconController) sharedInstance];

    _group = [group retain];
    [_group addObserver:self];
    [self _setDelegateOnCentralIconView];
}

- (void)setShowPreview:(BOOL)shouldShow
{
    BOOL didChange = (_showPreview != shouldShow);
    if (!_isOpen && didChange) {
        _showPreview = shouldShow;
        [self resetLayouts];
    }
}

- (void)setShowGrabbers:(BOOL)show
{
    _showGrabbers = show;
    if (show && !_showPreview && !_group.empty) {
        [_centralIconView stk_setImageViewScale:1.0];
        [self _addGrabbers];
        [_centralIconView stk_setImageViewScale:kCentralIconPreviewScale];
    }
    else if (_topGrabberView || _bottomGrabberView) {
        [self _removeGrabbers];
        if (!SCALE_CENTRAL_ICON) [_centralIconView stk_setImageViewScale:1.0f];
    }
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
    [self _setDelegateOnCentralIconView];
    for (SBIconView *iconView in _subappLayout) {
        iconView.delegate = delegate;
    }
}

- (void)_setDelegateOnCentralIconView
{
    _centralIconView.groupView = nil;
    [_centralIconView release];
    _centralIconView = [[[CLASS(SBIconViewMap) stk_homescreenMap] iconViewForIcon:_group.centralIcon] retain];
    _centralIconView.delegate = self.delegate;
    _centralIconView.groupView = self;
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
    if (CURRENTLY_SHOWS_PREVIEW) {
        [self _reallyConfigureSubappViews];
    }
}

- (void)_reallyConfigureSubappViews
{
    [_subappLayout release];
    _subappLayout = [[STKGroupLayout alloc] init];
    BOOL scaleDown = SCALE_CENTRAL_ICON;
    [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
        SBIconView *iconView = [self.iconViewSource groupView:self wantsIconViewForIcon:icon];
        iconView.iconLabelAlpha = 0.f;
        iconView.frame = _centralIconView.bounds;
        iconView.delegate = self.delegate;
        [_subappLayout addIcon:iconView toIconsAtPosition:pos];
        [self _setAlpha:0.f forBadgeAndLabelOfIconView:iconView];
        [self addSubview:iconView];
        [self _positionIconView:iconView inPosition:pos isLast:(idx == (c.count - 1)) scaleDown:scaleDown];

        if ([CLASS(SBIconController) instancesRespondToSelector:@selector(viewMap:configureIconView:)]) {
            SBIconController *controller = [CLASS(SBIconController) sharedInstance];
            [controller viewMap:[CLASS(SBIconViewMap) stk_homescreenMap] configureIconView:iconView];
        }
    }];
    if (SCALE_CENTRAL_ICON) {
        [_centralIconView stk_setImageViewScale:kCentralIconPreviewScale];
    }
}

- (void)_setupPreview
{
    BOOL scaleDown = SCALE_CENTRAL_ICON;
    [_subappLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx, BOOL *stop) {
        [self _positionIconView:iconView inPosition:position isLast:(idx == (currentArray.count - 1)) scaleDown:scaleDown];
    }];
}

- (void)_positionIconView:(SBIconView *)iconView inPosition:(STKLayoutPosition)position isLast:(BOOL)isLastInPosition scaleDown:(BOOL)scaleDown
{
    CGRect frame = _centralIconView.bounds;
    CGPoint newOrigin = frame.origin;

    // Only setup for preview if icon view is outside position
    if (CURRENTLY_SHOWS_PREVIEW && isLastInPosition) {
        CGFloat *memberToModify = (STKPositionIsVertical(position) ? &newOrigin.y : &newOrigin.x);
        CGFloat negator = (position == STKPositionTop || position == STKPositionLeft ? -1 : 1);
        *memberToModify += kPopoutDistance * negator;
        iconView.alpha = kSubappPreviewAlpha;
    }
    frame.origin = newOrigin;
    iconView.frame = frame;
    if (![iconView.icon isLeafIcon] && (_group.empty == NO)) {
        iconView.alpha = 0.f;
    }
    // Hide the label and badge
    [self _setAlpha:0.f forBadgeAndLabelOfIconView:iconView];
    if (scaleDown) {
        // Scale the icon back down to the smaller size
        [iconView stk_setImageViewScale:kSubappPreviewScale];
    }
}

- (void)_addGrabbers
{
    [self _removeGrabbers];

    CGRect iconImageFrame = [self _iconImageFrame];
    CGFloat grabberWidth = (floorf(iconImageFrame.size.width * 0.419354839) + 1.0);

    _topGrabberView = [[UIView new] autorelease];
    _topGrabberView.frame = (CGRect){{0, self.bounds.origin.y - kGrabberDistanceFromEdge - kGrabberHeight + 2.f}, {grabberWidth, kGrabberHeight}};
    _topGrabberView.center = (CGPoint){[_centralIconView iconImageCenter].x, _topGrabberView.center.y};

    _bottomGrabberView = ([_centralIconView isInDock] ? nil : [[UIView new] autorelease]);
    _bottomGrabberView.frame = (CGRect){{0, iconImageFrame.size.height + kGrabberDistanceFromEdge - 4.f}, {grabberWidth, kGrabberHeight}};
    _bottomGrabberView.center = (CGPoint){[_centralIconView iconImageCenter].x, _bottomGrabberView.center.y};

    _topGrabberView.layer.cornerRadius = _bottomGrabberView.layer.cornerRadius = (kGrabberHeight * 0.5f);
    _topGrabberView.layer.masksToBounds = _bottomGrabberView.layer.masksToBounds = YES;

    _UILegibilitySettings *legibilitySettings = [_centralIconView legibilitySettings];
    UIColor *color = ((legibilitySettings.style == 1) ? kGrabberLightColour : kGrabberDarkColour);
    _topGrabberView.backgroundColor = _bottomGrabberView.backgroundColor = color;

    _topGrabberOriginalFrame = _topGrabberView.frame;
    _bottomGrabberOriginalFrame = _bottomGrabberView.frame;
    [self addSubview:_topGrabberView];
    [self addSubview:_bottomGrabberView];
}

- (CGRect)_iconImageFrame
{
    return [_centralIconView convertRect:[_centralIconView iconImageFrame] toView:self];
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
    if (!_ignoreRecognizer && self.isOpen) {
        _ignoreRecognizer = YES;
        return;
    }
    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
            CGPoint translation = [sender translationInView:self];
            _isUpwardSwipe = ([sender velocityInView:self].y < 0);

            BOOL isHorizontalSwipe = !((fabs(translation.x / translation.y) < 5.0) || translation.x == 0);

            BOOL denyForConflictingActivation = NO;
            if (!STKActivationModeIsUpAndDown(_activationMode)) {
                BOOL isUpwardSwipeInSwipeDownMode = (_activationMode & STKActivationModeSwipeDown && _isUpwardSwipe);
                BOOL isDownwardSwipeInSwipeUpMode = (_activationMode & STKActivationModeSwipeUp && (_isUpwardSwipe == NO));
                denyForConflictingActivation = (isUpwardSwipeInSwipeDownMode || isDownwardSwipeInSwipeUpMode);
            }

            BOOL delegateDeniedOpen = (self.delegate && ![self.delegate shouldGroupViewOpen:self]);
            if (delegateDeniedOpen || isHorizontalSwipe || denyForConflictingActivation) {
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
            _lastDistanceFromCenter = fabs(subappView.frame.origin.y - _centralIconView.bounds.origin.y);
        }
        else if (!_hasVerticalIcons && STKPositionIsHorizontal(slot.position)) {
           _lastDistanceFromCenter = fabs(subappView.frame.origin.x - _centralIconView.bounds.origin.x);
        }
    }
    if (SCALE_CENTRAL_ICON) {
        if (_lastDistanceFromCenter <= midWayDistance) {
            // If the icons have not passed the halfway mark, modify their scale as necessary
            CGFloat stackIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kSubappPreviewScale);
            [subappView stk_setImageViewScale:stackIconTransformScale];
        }
        else {
            [subappView stk_setImageViewScale:1.f];
        }
    }
    if (CURRENTLY_SHOWS_PREVIEW) {
        if (slot.index == ([_subappLayout[slot.position] count] - 1)) {
            subappView.alpha = STKScaleNumber(_lastDistanceFromCenter, 0, midWayDistance, kSubappPreviewAlpha, 1.0);
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
    else if ([recognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        shouldBegin = ((_activationMode & STKActivationModeSwipeUp) || (_activationMode & STKActivationModeSwipeDown));
    }
    else if ([recognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        shouldBegin = (_activationMode & STKActivationModeDoubleTap);
    }
    if (_delegateFlags.shouldOpen) {
        shouldBegin = (shouldBegin && [self.delegate shouldGroupViewOpen:self]);
    }
    return shouldBegin;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recog shouldReceiveTouch:(UITouch *)touch
{
    BOOL shouldReceive = YES;
    if ([recog isKindOfClass:[UITapGestureRecognizer class]]) {
        shouldReceive = (_activationMode & STKActivationModeDoubleTap);
    }
    else if ([recog isKindOfClass:[UIPanGestureRecognizer class]]) {
        shouldReceive = ((_activationMode & STKActivationModeSwipeUp) || (_activationMode & STKActivationModeSwipeDown));
    }
    return shouldReceive;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)ogr
{
    return [self.delegate groupView:self shouldRecognizeGesturesSimultaneouslyWithGestureRecognizer:ogr];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if ([otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return YES;
    }
    return NO;
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
    if (_delegateFlags.willOpen) {
        [self.delegate groupViewWillOpen:self];
    }
    if (!_subappLayout) {
        [self _reallyConfigureSubappViews];
        [self _resetDisplacedIconLayout];
    }
    SBIconListView *listView = STKListViewForIcon(_centralIconView.icon);
    void(^animationBlock)(void) = ^{
        [_subappLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
            [self _setAlpha:1.0 forBadgeAndLabelOfIconView:iconView];
            CGPoint origin = [self _targetOriginForSubappSlot:(STKGroupSlot){pos, idx}];
            iconView.frame = (CGRect){origin, iconView.frame.size};
            [iconView stk_setImageViewScale:1.f];
            iconView.alpha = 1.f;
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
        if (_delegateFlags.didOpen) {
            [self.delegate groupViewDidOpen:self];
        }
    };
    [UIView animateWithDuration:kOpenAnimationDuration
                          delay:0.0
         usingSpringWithDamping:kOpenAnimationDamping
          initialSpringVelocity:kOpenAnimationVelocity
                        options:kDefaultAnimationOptions
                     animations:animationBlock
                     completion:completionBlock];
    [UIView animateWithDuration:kOpenAnimationFadeDuration delay:0.0 options:kDefaultAnimationOptions animations:^{
        if ([_centralIconView isInDock]) {
            for (SBIcon *icon in _displacedIconLayout) {
                [listView viewForIcon:icon].alpha = 0.f;
            }
        }
        [_centralIconView stk_setImageViewScale:1.f];
        [self _setAlphaForOtherIcons:kBackgroundFadeAlpha];
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
    if (_delegateFlags.willClose) {
        [self.delegate groupViewWillClose:self];
    }
    for (SBIconView *iconView in _subappLayout) {
        if ([iconView.icon isLeafIcon]) [iconView removeApexOverlay];
    }
    CGFloat scale = ((SCALE_CENTRAL_ICON) ? kCentralIconPreviewScale : 1.f);
    [self _performScaleAnimationOnCentralIconFromScale:(scale - 0.1f) toScale:scale];
    [UIView animateWithDuration:kCloseAnimationDuration delay:0.0 options:kDefaultAnimationOptions animations:^{
            [self _setAlphaForOtherIcons:1.f];
            [self _setupPreview];

            _topGrabberView.frame = _topGrabberOriginalFrame;
            _bottomGrabberView.frame = _bottomGrabberOriginalFrame;
            _topGrabberView.alpha = _bottomGrabberView.alpha = 1.f;

            if ([_centralIconView isInDock]) {
                [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:
                    ^(SBIcon *icon, STKLayoutPosition pos, NSArray *current, NSUInteger idx, BOOL *stop) {
                        SBIconView *iconView = [self _iconViewForIcon:icon];
                        if ([_centralIconView isInDock]) {
                            iconView.alpha = 1.f;
                        }
                    }
                ];
            }

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
            if (_delegateFlags.didClose) {
                [self.delegate groupViewDidClose:self];
            }
        }
    ];
}

- (void)_performScaleAnimationOnCentralIconFromScale:(CGFloat)fromScale toScale:(CGFloat)toScale
{
    [UIView animateWithDuration:(kCloseAnimationDuration * 0.6) delay:0 options:(UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState) animations:^{
        [_centralIconView stk_setImageViewScale:fromScale];
    } completion:^(BOOL done) {
        [UIView animateWithDuration:(kCloseAnimationDuration * 0.6) delay:0 options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState) animations:^{
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
    if (STKPositionIsVertical(slot.position)) {
        target.y += ([listView stk_realVerticalIconPadding] + iconSize.height) * factor;
    }
    else if (STKPositionIsHorizontal(slot.position)) {
        target.x += ([listView stk_realHorizontalIconPadding] + iconSize.width) * factor;
    }
    if ([_centralIconView isInDock]) {
        SBDockIconListView *dock = (SBDockIconListView *)STKListViewForIcon(_centralIconView.icon);
        SBRootFolderView *rootView = [[CLASS(SBIconController) sharedInstance] _rootFolderController].contentView;
        CGFloat pageControlHeight = ({
            SBIconListPageControl *pageControl = [rootView valueForKey:@"_pageControl"];
            fmaxf(pageControl.frame.size.height, 37.0);
        });
        target.y -= (pageControlHeight - (ISPAD() ? 40.0 : [dock stk_realVerticalIconPadding]));
        target.y += 2.0;
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
    CGFloat accessoryAlpha = STKScaleNumber(alpha, kBackgroundFadeAlpha, 1.0, 0.0, 1.0);
    void(^setter)(id, id) = ^(SBIconListView *listView, SBIcon *icon) {
        if ([icon isEqual:_group.centralIcon] || ([_centralIconView isInDock] && [ _displacedIconLayout[STKPositionTop] containsObject:icon])) {
            return;
        }
        SBIconView *view = [listView viewForIcon:icon];
        view.alpha = alpha;
        [self _setAlpha:alpha forBadgeAndLabelOfIconView:[listView viewForIcon:icon]];
        view.iconAccessoryAlpha = accessoryAlpha;
    };
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    SBIconListView *currentListView = STKCurrentListView();
    SBIconListView *dock = [controller dockListView];
    for (SBIcon *icon in [currentListView icons]) {
        setter(currentListView, icon);
    }
    for (SBIcon *icon in [dock icons]) {
        setter(dock, icon);
    }
    SBIconListPageControl *pageControl = [[controller _currentFolderController].contentView valueForKey:@"pageControl"];
    pageControl.alpha = alpha;
}

- (void)_setAlpha:(CGFloat)alpha forBadgeAndLabelOfIconView:(SBIconView *)iconView
{
    iconView.iconAccessoryAlpha = alpha;
    if ([_centralIconView _labelImage]) {
        iconView.iconLabelAlpha = alpha;
    }
    if (IS_8_1()) {
        [[iconView valueForKey:@"labelAccessoryView"] setAlpha:alpha];
    }
    else {
        [[iconView valueForKey:@"updatedMark"] setAlpha:alpha];
    }
}

- (void)_setAlphaForDisplacedIcons:(CGFloat)alpha
{
    for (SBIcon *icon in _displacedIconLayout) {
        [self _iconViewForIcon:icon].alpha = alpha;
    }
}

- (SBIconView *)_iconViewForIcon:(SBIcon *)icon
{
    return [[CLASS(SBIconViewMap) stk_homescreenMap] mappedIconViewForIcon:icon];
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
        [self _setAlpha:1.f forBadgeAndLabelOfIconView:iconView];
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
    DLog();
    [UIView animateWithDuration:kPlaceholderAddDuration delay:0.0 usingSpringWithDamping:0.6f initialSpringVelocity:0.3f options:kDefaultAnimationOptions
        animations:^{
            [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
                if ([icon isPlaceholder]) {
                    SBIconView *iconView = [[[self.iconViewSource groupView:self wantsIconViewForIcon:icon] retain] autorelease];
                    if (![_centralIconView _labelImage]) {
                        iconView.iconLabelAlpha = 0.f;
                    }
                    iconView.frame = (CGRect){[self _targetOriginForSubappSlot:(STKGroupSlot){pos, idx}], iconView.frame.size};
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
    } completion:nil];
}

- (void)groupWillRemovePlaceholders:(STKGroup *)group
{
    NSMutableArray *viewsToRemove = [NSMutableArray array];
    [UIView animateWithDuration:kPlaceholderRemoveDuration delay:0 options:kDefaultAnimationOptions animations:^{
        [_group.layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition pos, NSArray *c, NSUInteger idx, BOOL *stop) {
            // we cannot mutate _subappLayout during iteration, so iterate over _group.layout
            // and store the views to be removed in a separate array
            SBIconView *iconView = _subappLayout[pos][idx];
            if ([icon isPlaceholder]) {
                [iconView.superview sendSubviewToBack:iconView];
                iconView.frame = (CGRect){CGPointZero, iconView.frame.size};
                [viewsToRemove addObject:iconView];
            }
            iconView.apexOverlayView.alpha = 0.f;
        }];
        [self _unhideIconsForPlaceholders];
    } completion:^(BOOL finished) {
        for (SBIconView *iconView in _subappLayout) {
            if ([iconView.icon isLeafIcon]) {
                [iconView removeApexOverlay];
            }
        }
        for (SBIconView *view in viewsToRemove) {
            [self.iconViewSource groupView:self willRelinquishIconView:view];
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
    SBIconListView *listView = [[[CLASS(SBIconController) sharedInstance] _currentFolderController] currentIconListView];
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
        iconView.alpha = kBackgroundFadeAlpha;
    }
    [_iconsHiddenForPlaceholders release];
    _iconsHiddenForPlaceholders = nil;
}

@end
