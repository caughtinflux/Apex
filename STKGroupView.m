#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "STKGroup.h"
#import "STKGroupView.h"
#import "SBIconListView+ApexAdditions.h"

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
    [_group release];
    [_panRecognizer release];
    [_tapRecognizer release];
    [super dealloc];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.frame = self.superview.bounds;
    _centralIconView._iconImageView.alpha = 0.0f;
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
        [self addSubview:iconView];
    }];
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

- (void)_panned:(UIPanGestureRecognizer *)recognizer
{
    static CGFloat targetDistance = 0.f;
    static BOOL isUpwardSwipe;
    static BOOL cancelledPanRecognizer;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        CGFloat defaultHeight = [objc_getClass("SBIconView") defaultIconSize].height;
        CGFloat verticalPadding = [STKListViewForIcon(_group.centralIcon) stk_realVerticalIconPadding];
        targetDistance = verticalPadding + defaultHeight;

        CGPoint translation = [recognizer translationInView:self];
        isUpwardSwipe = ([recognizer velocityInView:self].y < 0);
        BOOL isHorizontalSwipe = !((fabsf(translation.x / translation.y) < 5.0) || translation.x == 0);
        BOOL isUpwardSwipeInSwipeDownMode = ((self.activationMode == STKActivationModeSwipeDown) && isUpwardSwipe);
        BOOL isDownwardSwipeInSwipeUpMode = ((self.activationMode == STKActivationModeSwipeUp) && !isUpwardSwipe);
        
        if (isHorizontalSwipe || isUpwardSwipeInSwipeDownMode || isDownwardSwipeInSwipeUpMode) {
            cancelledPanRecognizer = YES;
            return;
        }
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged) {
        if (cancelledPanRecognizer) {
            return;
        }
        CFTimeInterval offset = MIN((fabsf([recognizer translationInView:self].y) / targetDistance), 0.99f);
        [self _moveSubappsAlongPathsToOffset:offset];
    }
    else if (recognizer.state == UIGestureRecognizerStateEnded) {
        targetDistance = 0.f;
        isUpwardSwipe = NO;
        cancelledPanRecognizer = NO;
    }
}

- (void)_moveSubappsAlongPathsToOffset:(CFTimeInterval)timeOffset
{
    [_subappLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL *stop) {
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        animation.duration = 1.0;
        animation.speed = 0.0;
        animation.fillMode = kCAFillModeForwards;
        animation.removedOnCompletion = NO;
        UIBezierPath *path = [UIBezierPath bezierPath];            
        [path moveToPoint:iconView.layer.position];
        [path addLineToPoint:[self _targetPositionForSubappSlot:(STKGroupSlot){position, index}]];
        animation.path = path.CGPath;

        animation.timeOffset = timeOffset;
        [iconView.layer addAnimation:animation forKey:@"ApexSubappAnimation"];
    }];
}

@end
