#import "STKOverlayIcons.h"
#import "STKConstants.h"

%subclass STKEmptyIcon : SBIcon

- (id)getIconImage:(NSInteger)imgType
{
    return [[[UIImage alloc] init] autorelease];
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
    return [[[UIImage alloc] init] autorelease];
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
