#import "STKIconViewRecycler.h"
#import "STKConstants.h"

@interface STKIconViewRecycler ()
{
    NSMapTable *_recycledIconViews;
    NSUInteger _maxRecycledIconViews;
}
@end

@implementation STKIconViewRecycler

- (instancetype)init
{
    if ((self = [super init])) {
        _recycledIconViews = [[NSMapTable strongToStrongObjectsMapTable] retain];
        _maxRecycledIconViews = [[[CLASS(SBIconController) sharedInstance] valueForKey:@"maxIconViewsInHierarchy"] unsignedIntegerValue] / 2;
    }
    return self;
}

- (void)dealloc
{
    [_recycledIconViews removeAllObjects];
    [_recycledIconViews release];
    [super dealloc];
}

- (SBIconView *)iconViewForIcon:(SBIcon *)icon
{
    Class classForIconView = [icon iconViewClassForLocation:SBIconLocationHomeScreen];
    SBIconView *iconView = [[[classForIconView alloc] initWithDefaultSize] autorelease];
    iconView.icon = icon;
    return iconView;
}

- (void)recycleIconView:(SBIconView *)iconView
{
    return;
}

- (SBIconView *)groupView:(STKGroupView *)groupView wantsIconViewForIcon:(SBIcon *)icon
{
    return [self iconViewForIcon:icon];
}

- (void)groupView:(STKGroupView *)groupView willRelinquishIconView:(SBIconView *)iconView
{
    [self recycleIconView:iconView];
}

@end
