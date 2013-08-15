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
        [self setNeedsLayout];
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

    _iconView.frame = (CGRect){{_iconView.frame.origin.x, _iconView.frame.origin.y}, {_iconView.frame.size.width, [[_iconView class] defaultIconImageSize].height}};

    SBIconLabelImageView *labelView = [_iconView valueForKey:@"_labelView"];
    labelView.frame = (CGRect){{CGRectGetMaxX(_iconView.bounds) + 5, ((_iconView.iconImageView.image.size.height * 0.5f) - (labelView.frame.size.height * 0.5f))}, 
                               labelView.frame.size};
}

@end

