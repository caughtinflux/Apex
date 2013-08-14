#import "STKSelectionViewCell.h"
#import "STKConstants.h"

#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

@implementation STKSelectionViewCell
{
    SBIconView *_iconView;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _iconView = [[objc_getClass("SBIconView") alloc] initWithDefaultSize];
        _iconView.location = 1337;

        [self addSubview:_iconView];
    }

    return self;
}

- (void)setIcon:(SBIcon *)icon
{
    if (_icon != icon) {
        [_icon release];
        _icon = [icon retain];

        [_iconView setIcon:_icon];
        [self setNeedsLayout];
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    SBIconLabelImageView *labelView = [_iconView valueForKey:@"_labelView"];
    labelView.frame = (CGRect){ {CGRectGetMaxX(_iconView.frame) + 10, CGRectGetMidY(self.bounds)}, labelView.frame.size};
}

@end
