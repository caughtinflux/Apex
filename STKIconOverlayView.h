#import <UIKit/UIKit.h>

extern NSString * const STKIconOverlayBlurQualityDefault;
extern NSString * const STKIconOverlayBlurQualityLow;

@interface STKIconOverlayView : UIView

/**
 Quality of the blur. The lower the quality, the more performant the blur. Must be one of `CKBlurViewQualityDefault` or `CKBlurViewQualityLow`. Defaults to `CKBlurViewQualityDefault`.
 */
@property (nonatomic, copy) NSString *blurQuality;

/**
 Radius of the Gaussian blur. Defaults to 5.0.
 */
@property (nonatomic) CGFloat blurRadius;

@end
