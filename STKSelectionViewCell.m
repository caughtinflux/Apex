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
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _iconView = [[objc_getClass("SBIconView") alloc] initWithDefaultSize];
        _iconView.location = (SBIconViewLocation)1337;

        _iconView.clipsToBounds = NO;

        [self addSubview:_iconView];
        [self setNeedsLayout];
    }

    return self;
}

- (void)dealloc
{
    [_iconView release];
    [_icon release];

    [super dealloc];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    _iconView.frame = (CGRect){{_iconView.frame.origin.x, _iconView.frame.origin.y}, {_iconView.frame.size.width, [[_iconView class] defaultIconImageSize].height}};
    SBIconLabelImageView *labelView = [_iconView valueForKey:@"_labelView"];

    CGFloat referencePoint = (_position == STKSelectionCellPositionRight ? CGRectGetMaxX(_iconView.bounds) : _iconView.bounds.origin.x - labelView.frame.size.width - 12);
    labelView.frame = (CGRect){{referencePoint + 5, ((_iconView.iconImageView.image.size.height * 0.5f) - (labelView.frame.size.height * 0.5f))}, 
                               labelView.frame.size};
}

- (void)setIcon:(SBIcon *)icon
{
    if (_icon != icon) {
        [_icon release];
        _icon = [icon retain];

        [_iconView setIcon:_icon];

        CGFloat alpha = _iconView.icon.isPlaceholder ? 0.f : 1.f;
        
        ((UIImageView *)[_iconView valueForKey:@"_shadow"]).alpha = alpha;
        [_iconView setIconLabelAlpha:alpha];
        ((UIView *)[_iconView valueForKey:@"_accessoryView"]).alpha = alpha;

        [self setNeedsLayout];
    }
}

- (void)setPosition:(STKSelectionCellPosition)position
{
    if (_position != position) {
        _position = position;
        [self setNeedsLayout];
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *overrideView = [self viewWithTag:self.hitTestOverrideSubviewTag];
    if (overrideView) {
        CGRect frame = [overrideView.superview convertRect:overrideView.frame toView:self];
        if (CGRectContainsPoint(frame, point)) {
            return overrideView;
        }
    }
    
    return [super hitTest:point withEvent:event];
}

@end

