#import "STKOverlayIcons.h"
#import "STKConstants.h"

static UIImage *_img = nil;

%subclass STKEmptyIcon : SBIcon

+ (void)load
{
    _img = [[UIImage alloc] init];
}

- (id)getIconImage:(NSInteger)imgType
{
    return _img;
}

- (BOOL)isEmptyPlaceholder
{
    return YES;
}

- (BOOL)isPlaceholder
{
    return NO;
}

- (id)nodeIdentifier
{
    return self;
}

%end

%subclass STKPlaceholderIcon : SBIcon

- (id)getIconImage:(NSInteger)imgType
{
    return _img;
}

- (BOOL)isPlaceholder
{
    return YES;
}

- (id)nodeIdentifier
{
    return self;
}

%end
