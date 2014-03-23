#import "STKSelectionHeaderView.h"
#import "STKConstants.h"
#import <SpringBoard/SpringBoard.h>

@implementation STKSelectionHeaderView
{
    SBWallpaperEffectView *_wallpaperEffectView;
    UILabel *_titleLabel;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _wallpaperEffectView = [[[CLASS(SBWallpaperEffectView) alloc] initWithWallpaperVariant:SBWallpaperVariantHomeScreen] autorelease];
        _wallpaperEffectView.frame = self.bounds;
        _wallpaperEffectView.center = (CGPoint){CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds)};
        _wallpaperEffectView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        [_wallpaperEffectView setStyle:2];

        _titleLabel = [[[UILabel alloc] initWithFrame:self.bounds] autorelease];
        _titleLabel.autoresizingMask = _wallpaperEffectView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        _titleLabel.font = [UIFont fontWithName:@"Helvetica Neue" size:18.f];
        _titleLabel.textColor = [UIColor colorWithWhite:1.f alpha:0.7f];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        
        [self addSubview:_wallpaperEffectView];
        [self addSubview:_titleLabel];
    }
    return self;
}

- (void)setHeaderTitle:(NSString *)title
{
    _titleLabel.text = title;
}

- (NSString *)headerTitle
{
    return _titleLabel.text;
}

@end
