#import "STKGroup.h"
#import "STKConstants.h"

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

NSString * const STKGroupCentralIconKey = @"centralIcon";
NSString * const STKGroupLayoutKey      = @"layout";
NSString * const STKGroupCoordinateKey  = @"coordinate";

@implementation STKGroup
{
    STKGroupLayout *_layout;
    STKGroupLayout *_placeholderLayout;
    NSHashTable *_observers;
}

- (instancetype)initWithCentralIcon:(SBIcon *)icon layout:(STKGroupLayout *)layout
{
    if ((self = [super init])) {
        _centralIcon = [icon retain];
        _layout = [layout retain];
        [self _commonInit];
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
        [self _commonInit];
    }
    return self;
}

- (void)_commonInit
{
    _observers = [[NSHashTable alloc] initWithOptions:NSHashTableWeakMemory capacity:0];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editingEnded:) name:STKEditingEndedNotificationName object:nil];
    if (!self.empty) {
        // Ensure icon images are cached
        for (SBIcon *icon in _layout) {
            [icon getIconImage:2];
        }
    }
}

- (void)dealloc
{
    [_layout release];
    [_placeholderLayout release];
    [_observers removeAllObjects];
    [_observers release];
    [_centralIcon release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p centralIcon: %@ layout: %@ observers: %zd>", [self class], self, _centralIcon.leafIdentifier, _layout, _observers.count];
}

- (NSDictionary *)dictionaryRepresentation
{
    return @{
        STKGroupCentralIconKey: [_centralIcon leafIdentifier] ?: @"",
        STKGroupLayoutKey: [_layout identifierDictionary] ?: @{},
        STKGroupCoordinateKey: STKDictionaryFromCoordinate(_lastKnownCoordinate)
    };
}

- (BOOL)hasPlaceholders
{
    return !!(_placeholderLayout);
}

- (BOOL)empty
{
    return (_state == STKGroupStateEmpty);
}

- (void)relayoutForNewCoordinate:(SBIconCoordinate)coordinate
{
    if ((coordinate.row == _lastKnownCoordinate.row && coordinate.col == _lastKnownCoordinate.col)) {
        return;
    }
    _lastKnownCoordinate = coordinate;
    [self forceRelayout];
}

- (void)forceRelayout
{
    if (_state == STKGroupStateEmpty) {
        [_layout release];
        _layout = [[STKGroupLayoutHandler emptyLayoutForIconAtLocation:[STKGroupLayoutHandler locationForIcon:_centralIcon]] retain];
    } 
    else {
        STKGroupLayout *newLayout = [STKGroupLayoutHandler correctLayoutForGroupIfNecessary:self];
        if (newLayout) {
            [_layout release];
            _layout = [newLayout retain];
        }
    }
    // Notify observers irrespective of whether we needed to relayout    
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs groupDidRelayout:self];
    } forSelector:@selector(groupDidRelayout:)];
}

- (void)replaceIconInSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon
{
    SBIcon *iconToReplace = [[[_layout iconInSlot:slot] retain] autorelease];
    [_layout setIcon:icon inSlot:slot];
    BOOL iconToAddIsPlaceholder = ![icon isLeafIcon];
    if (iconToAddIsPlaceholder) {
        [_placeholderLayout addIcon:icon toIconsAtPosition:slot.position];
    }
    [self _updateState];
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs group:self replacedIcon:iconToReplace inSlot:slot withIcon:icon];
    } forSelector:@selector(group:replacedIcon:inSlot:withIcon:)];
}

- (void)removeIconInSlot:(STKGroupSlot)slot
{
    SBIcon *removedIcon = [[[_layout iconInSlot:slot] retain] autorelease];
    [_layout removeIcon:removedIcon fromIconsAtPosition:slot.position];
    _state = STKGroupStateDirty;
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs group:self removedIcon:removedIcon inSlot:slot];
    } forSelector:@selector(group:removedIcon:inSlot:)];
}

- (void)addPlaceholders
{
    if (_placeholderLayout) {
        return;
    }
    _state = STKGroupStateDirty;
    _placeholderLayout = [[STKGroupLayoutHandler placeholderLayoutForGroup:self] retain];
    for (STKLayoutPosition pos = STKPositionTop; pos <= STKPositionRight; pos++) {
        [_layout addIcons:_placeholderLayout[pos] toIconsAtPosition:pos];
    }
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs groupDidAddPlaceholders:self];
    } forSelector:@selector(groupDidAddPlaceholders:)];
}

- (void)removePlaceholders
{
    if (_state != STKGroupStateDirty) {
        return;
    }
    [self _forceUdpateState];
    if (_state == STKGroupStateEmpty) {
        [_placeholderLayout release];
        _placeholderLayout = nil;
    }
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs groupWillRemovePlaceholders:self];
    } forSelector:@selector(groupWillRemovePlaceholders:)];
    for (STKLayoutPosition pos = STKPositionTop; pos <= STKPositionRight; pos++) {
        [_layout removeIcons:_placeholderLayout[pos] fromIconsAtPosition:pos];
    }
    [_placeholderLayout release];
    _placeholderLayout = nil;

    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs groupDidRemovePlaceholders:self];
    } forSelector:@selector(groupDidRemovePlaceholders:)];
}

- (void)finalizeState
{
    if (_state != STKGroupStateDirty) {
        STKLog(@"Group state is not dirty, simply notifying observers.");
        goto notifyObservers;
    }
    STKGroupLayout *newLayout = [[STKGroupLayout alloc] init];
    // keep only the leaf icons
    [_layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL *stop) {
        if ([icon isLeafIcon]) {
            CLog(@"Finalization: Adding %@ to new layout", icon);
            [newLayout addIcon:icon toIconsAtPosition:position];
        }
    }];
    if ([newLayout allIcons].count > 0) {
        // move to newLayout only if it has any icons
        CLog(@"Finalization: Using new layout");
        [_layout release];
        _layout = newLayout;
        _state = STKGroupStateNormal;
    }
    else {
        // If newLayout doesn't have any icons, we transition to STKGroupStateEmpty!
        CLog(@"Finalization: New layout is empty, adjusting state to match");
        [newLayout release];
        _state = STKGroupStateEmpty;
        [self forceRelayout];
    }
    [_placeholderLayout release];
    _placeholderLayout = nil;

notifyObservers:
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs groupDidFinalizeState:self];
    } forSelector:@selector(groupDidFinalizeState:)];
}

- (void)_editingEnded:(NSNotification *)notf
{
    SBIconCoordinate coord = [STKGroupLayoutHandler coordinateForIcon:_centralIcon];
    [self relayoutForNewCoordinate:coord];
}

- (void)addObserver:(id<STKGroupObserver>)observer
{
    [_observers addObject:observer];
}

- (void)removeObserver:(id<STKGroupObserver>)observer
{
    [_observers removeObject:observer];     
}

- (void)_updateState
{
    if (_state == STKGroupStateDirty) {
        return;
    }
    [self _forceUdpateState];
}

- (void)_forceUdpateState
{
    NSUInteger emptyIconCount = 0;
    NSUInteger realIconCount = 0;
    for (SBIcon *icon in _layout) {
        if (![icon isLeafIcon]) {
            emptyIconCount++;
        }
        else {
            realIconCount++;
        }
    }
    if (realIconCount > 0 && emptyIconCount > 0) {
        // we need to process the icons to get rid of the empty placeholders
        _state = STKGroupStateDirty;
    }
    else if (realIconCount > 0 && emptyIconCount == 0) {
        _state = STKGroupStateNormal;
    }
    else {
        _state = STKGroupStateEmpty;
    }
}

- (void)_enumerateObserversUsingBlock:(void(^)(id<STKGroupObserver>))block forSelector:(SEL)sel
{
    for (id<STKGroupObserver> obs in [[_observers objectEnumerator] allObjects]) {
        if ([obs respondsToSelector:sel]) {
            block(obs);
        }
    }
}

@end
