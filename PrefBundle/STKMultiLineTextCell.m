#import "STKMultiLineTextCell.h"
#import "Localization.h"

@implementation STKMultiLineTextCell

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat inset = 10.0;
    CGRect frame = CGRectInset(self.bounds, inset, inset);
    if (ISPAD()) {
    	frame.size.width -= 50.f;
    }
    self.textLabel.frame = frame;
    self.textLabel.numberOfLines = 0;
    self.textLabel.attributedText = [[[NSAttributedString alloc] initWithString:self.textLabel.text
                                                                     attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16.f]}] autorelease];
}

@end
