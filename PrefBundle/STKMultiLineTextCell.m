#import "STKMultiLineTextCell.h"

@implementation STKMultiLineTextCell

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.textLabel.frame = CGRectInset(self.bounds, 10.f, 10.f);
    self.textLabel.numberOfLines = 0;
    self.textLabel.attributedText = [[[NSAttributedString alloc] initWithString:self.textLabel.text
                                                                     attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16.f]}] autorelease];
}

@end
