#import "STKConstants.h"

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

NSString * const STKGroupCentralIconKey = @"STKGroupCentralIcon";
NSString * const STKGroupLayoutKey      = @"STKGroupLayout";
NSString * const STKGroupCoordinateKey  = @"STKLastKnownCoordinate";

@implementation STKGroup
{
    STKGroupLayout *_layout;
    STKGroupView *_view;
    NSHashTable *_observers;
}

- (instancetype)initWithCentralIcon:(SBIcon *)icon layout:(STKGroupLayout *)layout
{
    if ((self = [super init])) {
        _centralIcon = [icon retain];
        _layout = [layout retain];
        _observers = [[NSHashTable alloc] initWithOptions:NSHashTableWeakMemory capacity:0];
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)repr
{
    NSParameterAssert([repr allKeys].count > 0);
    if ((self = [super init])) {
        NSString *iconID = repr[STKGroupCentralIconKey];
        _centralIcon = [[(SBIconModel *)[[CLASS(SBIconController) sharedInstance] model] expectedIconForDisplayIdentifier:iconID] retain];
        _layout = [[STKGroupLayout alloc] initWithIdentifierDictionary:repr[STKGroupLayoutKey]];
        _lastKnownCoordinate = STKCoordinateFromDictionary(repr[STKGroupCoordinateKey]);
    }
    return self;
}

- (void)dealloc
{
    _view.group = nil;
    [_view release];
    [_layout release];
    [_observers removeAllObjects];
    [_observers release];
    [_centralIcon release];
    [super dealloc];
}

- (STKGroupLayout *)layout
{
    return _layout;
}

- (NSDictionary *)dictionaryRepresentation
{
    return @{
        STKGroupCentralIconKey: [_centralIcon leafIdentifier] ?: @"",
        STKGroupLayoutKey: [_layout identifierDictionary] ?: @{},
        STKGroupCoordinateKey: STKDictionaryFromCoordinate(_lastKnownCoordinate)
    };
}

- (void)addObserver:(id<STKGroupObserver>)observer
{
    [_observers addObject:observer];
}

- (void)removeObserver:(id<STKGroupObserver>)observer
{
    [_observers removeObject:observer];     
}

- (SBIconView *)_iconViewForIcon:(SBIcon *)icon
{
    return [[CLASS(SBIconViewMap) homescreenMap] mappedIconViewForIcon:icon];
}

- (BOOL)iconViewDisplaysCloseBox:(SBIconView *)iconView
{
    return [[CLASS(SBIconController) sharedInstance] iconViewDisplaysBadges:iconView];
}

- (BOOL)iconViewDisplaysBadges:(SBIconView *)iconView
{
    return [[CLASS(SBIconController) sharedInstance] iconViewDisplaysBadges:iconView];
}

- (BOOL)icon:(SBIconView *)iconView canReceiveGrabbedIcon:(SBIcon *)grabbedIcon
{
    return NO;
}

- (void)iconTapped:(SBIconView *)iconView
{
    [iconView.icon launchFromLocation:SBIconLocationHomeScreen];
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return YES;
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    // TODO Editing?
}

@end
