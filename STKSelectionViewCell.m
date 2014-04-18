#import "STKSelectionViewCell.h"
#import "STKConstants.h"
#import <SpringBoard/SpringBoard.h>

@implementation STKSelectionViewCell
{
    SBIconView *_iconView;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _iconView = [[[CLASS(SBIconView) alloc] initWithDefaultSize] autorelease];
        _iconView.delegate = self;
        [self.contentView addSubview:_iconView];
    }
    return self;
}

- (void)iconTapped:(SBIconView *)iconView
{
    __block STKSelectionViewCell *wSelf = self;
    self.tapHandler(wSelf);
    [iconView setHighlighted:NO];
}

- (void)layoutSubviews
{
    _iconView.center = (CGPoint){CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds)};
    [_iconView setHighlighted:NO];
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return YES;
}

- (void)icon:(SBIconView *)iconView touchEnded:(BOOL)ended {}
- (void)icon:(SBIconView *)iconView touchMoved:(UITouch *)touch {}
- (void)iconTouchBegan:(SBIconView *)iconView {}
- (void)iconHandleLongPress:(SBIconView *)iconView {}

@end
