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
    if (coordinate.row == _lastKnownCoordinate.row && coordinate.col == _lastKnownCoordinate.col) {
        return;
    }
    if (_state == STKGroupStateEmpty) {
        [_layout release];
        _layout = [[STKGroupLayoutHandler emptyLayoutForIconAtLocation:[STKGroupLayoutHandler locationForIcon:_centralIcon]] retain];
    }
    _lastKnownCoordinate = coordinate;
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs groupDidRelayout:self];
    } forSelector:@selector(groupDidRelayout:)];
}

- (void)replaceIconInSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon
{
    SBIcon *iconToReplace = [[[_layout iconInSlot:slot] retain] autorelease];
    [_layout setIcon:icon inSlot:slot];
    [self _updateState];
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs group:self replacedIcon:iconToReplace inSlot:slot withIcon:icon];
    } forSelector:@selector(group:replacedIcon:inSlot:withIcon:)];
}

- (void)addPlaceholders
{
    if (_placeholderLayout) {
        goto notifyObs;
    }
    _state = STKGroupStateDirty;
    _placeholderLayout = [[STKGroupLayoutHandler placeholderLayoutForGroup:self] retain];
    for (STKLayoutPosition pos = STKPositionTop; pos <= STKPositionRight; pos++) {
        [_layout addIcons:_placeholderLayout[pos] toIconsAtPosition:pos];
    }
notifyObs:
    [self _enumerateObserversUsingBlock:^(id<STKGroupObserver> obs) {
        [obs groupDidAddPlaceholders:self];
    } forSelector:@selector(groupDidAddPlaceholders:)];
}

- (void)removePlaceholders
{
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
        goto notifyObservers;
    }
    STKGroupLayout *newLayout = [[STKGroupLayout alloc] init];
    // keep only the leaf icons
    [_layout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index, BOOL *stop) {
        if ([icon isLeafIcon]) {
            [newLayout addIcon:icon toIconsAtPosition:position];
        }
    }];
    [_layout release];
    _layout = newLayout;
    _state = STKGroupStateNormal;

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
    NSUInteger emptyIconCount = 0;
    NSUInteger realIconCount = 0;
    for (SBIcon *icon in _layout) {
        if ([icon isEmptyPlaceholder] || [icon isPlaceholder]) {
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
