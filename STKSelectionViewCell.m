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
        if ([CLASS(SBIconView) instancesRespondToSelector:@selector(initWithDefaultSize)]) {
            _iconView = [[[CLASS(SBIconView) alloc] initWithDefaultSize] autorelease];
        }
        else if ([CLASS(SBIconView) instancesRespondToSelector:@selector(initWithContentType:)]) {
            _iconView = [[[CLASS(SBIconView) alloc] initWithContentType:0] autorelease];
        }
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
