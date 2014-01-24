#import "STKIconOverlayView.h"

@interface CABackdropLayer : CALayer

@end

@interface CAFilter : NSObject

+ (instancetype)filterWithName:(NSString *)name;

@end

@interface STKIconOverlayView ()

@property (nonatomic, assign) CAFilter *blurFilter;

@end

extern NSString * const kCAFilterGaussianBlur;

NSString * const STKIconOverlayBlurQualityDefault = @"default";
NSString * const STKIconOverlayBlurQualityLow = @"low";

static NSString * const STKBlurQualityKey = @"inputQuality";
static NSString * const STKBlurRadiusKey = @"inputRadius";
static NSString * const STKIconOverlayBoundsKey = @"inputBounds";
static NSString * const STKIconOverlayHardEdgesKey = @"inputHardEdges";


@implementation STKIconOverlayView

+ (Class)layerClass
{
    return [CABackdropLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        CAFilter *filter = [CAFilter filterWithName:kCAFilterGaussianBlur];
        self.layer.filters = @[filter];
        self.blurFilter = filter;
        self.blurQuality = STKIconOverlayBlurQualityDefault;
        self.blurRadius = 5.0f;
        self.blurEdges = YES;
    }
    return self;
}

- (void)setQuality:(NSString *)quality
{
    [self.blurFilter setValue:quality forKey:STKBlurQualityKey];
}

- (NSString *)quality
{
    return [self.blurFilter valueForKey:STKBlurQualityKey];
}

- (void)setBlurRadius:(CGFloat)radius
{
    [self.blurFilter setValue:[NSNumber numberWithFloat:radius] forKey:STKBlurRadiusKey];
}

- (CGFloat)blurRadius
{
    return [[self.blurFilter valueForKey:STKBlurRadiusKey] floatValue];
}

- (void)setBlurCroppingRect:(CGRect)croppingRect
{
    [self.blurFilter setValue:[NSValue valueWithCGRect:croppingRect] forKey:STKIconOverlayBoundsKey];
}

- (CGRect)blurCroppingRect
{
    NSValue *value = [self.blurFilter valueForKey:STKIconOverlayBoundsKey];
    return value ? [value CGRectValue] : CGRectNull;
}

- (void)setBlurEdges:(BOOL)blurEdges
{
    [self.blurFilter setValue:[NSNumber numberWithBool:!blurEdges] forKey:STKIconOverlayHardEdgesKey];
}

- (BOOL)blurEdges
{
    return ![[self.blurFilter valueForKey:STKIconOverlayHardEdgesKey] boolValue];
}

@end