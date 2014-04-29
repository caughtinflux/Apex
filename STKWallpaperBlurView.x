#import "STKWallpaperBlurView.h"
#import "STKConstants.h"

%subclass STKWallpaperBlurView : SBWallpaperEffectView

- (void)layoutSubviews
{
	%orig();
	self.layer.mask = self.mask;
}

- (void)setStyle:(NSInteger)style
{
	%orig(style);
	self.mask = self.mask;
}

%new
- (void)setMask:(CALayer *)mask
{
	objc_setAssociatedObject(self, @selector(apexMask), mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	self.layer.mask = mask;
}

%new
- (CALayer *)mask
{
	return objc_getAssociatedObject(self, @selector(apexMask));
}

%end
