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
        _iconView.center = (CGPoint){(CGRectGetWidth(frame) * 0.5f), (CGRectGetHeight(frame) * 0.5f)};
    }
    return self;
}

- (void)iconTapped:(SBIconView *)iconView
{
    __block STKSelectionViewCell *wSelf = self;
    self.tapHandler(wSelf);
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return YES;
}

@end
