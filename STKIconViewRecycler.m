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
        _maxRecycledIconViews = [[[CLASS(SBIconController) sharedInstance] valueForKey:@"maxIconViewsInHierarchy"] unsignedIntegerValue] / 4;
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
    Class classForIconView = nil;
    if ([icon respondsToSelector:@selector(iconViewClassForLocation:)]) {
        classForIconView = [icon iconViewClassForLocation:SBIconLocationHomeScreen];
    }
    else if ([[CLASS(SBIconController) sharedInstance] respondsToSelector:@selector(iconViewClassForIcon:location:)]) {
        classForIconView = [[CLASS(SBIconController) sharedInstance] iconViewClassForIcon:icon location:SBIconLocationHomeScreen];
    }
    else {
        CLog(@"No class for iconView! :(");
    }
    NSMutableSet *set = [_recycledIconViews objectForKey:classForIconView];
    SBIconView *iconView = [[[set anyObject] retain] autorelease];
    if (!iconView) {
        if ([classForIconView instancesRespondToSelector:@selector(initWithDefaultSize)]) {
            iconView = [[[classForIconView alloc] initWithDefaultSize] autorelease];
        }
        else if ([classForIconView instancesRespondToSelector:@selector(initWithContentType:)]) {
            iconView = [[[classForIconView alloc] initWithContentType:0] autorelease];
        }
    }
    iconView.icon = icon;
    [set removeObject:iconView];
    return iconView;
}

- (void)recycleIconView:(SBIconView *)iconView
{
    if ([iconView respondsToSelector:@selector(prepareForRecycling)]) {
        [iconView prepareForRecycling];
    }
    else if ([iconView respondsToSelector:@selector(prepareForReuse)]) {
        [iconView prepareForReuse];
    }
    NSMutableSet *set = [_recycledIconViews objectForKey:[iconView class]];
    if (!set) {
        set = [NSMutableSet new];
        [_recycledIconViews setObject:set forKey:[iconView class]];
    }
    if (set.count < _maxRecycledIconViews) {
        [set addObject:iconView];
    }
    [iconView removeFromSuperview];
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
