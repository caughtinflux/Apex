#import "STKIconLayout.h"
#import "STKConstants.h"

#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>

NSString * const STKTopIconsKey = @"TopIcons";
NSString * const STKBottomIconsKey = @"BottomIcons";
NSString * const STKLeftIconsKey = @"LeftIcons";
NSString * const STKRightIconsKey = @"RightIcons";

@interface STKIconLayout ()
{
    NSMutableArray      *_topIcons;
    NSMutableArray      *_bottomIcons;
    NSMutableArray      *_leftIcons;
    NSMutableArray      *_rightIcons;
    NSArray             *_allIcons;
    NSMutableDictionary *_dictRepr;
    BOOL                 _hasBeenModified;
} 
// Returns a pointer to a non-nil array ivar for pos
- (NSMutableArray **)_nonNilArrayForPosition:(STKLayoutPosition)pos;
@end

@implementation STKIconLayout

// SublimeClang throws an errors on @(somePos). Really. Annoying
#define TO_NUMBER(_i) [NSNumber numberWithInteger:_i]
+ (NSArray *)allPositions
{
    return @[TO_NUMBER(STKLayoutPositionTop), TO_NUMBER(STKLayoutPositionBottom), TO_NUMBER(STKLayoutPositionLeft), TO_NUMBER(STKLayoutPositionRight)];
}

+ (instancetype)layoutWithDictionary:(NSDictionary *)dict
{
    return [[[self alloc] initWithDictionary:dict] autorelease];
}

+ (instancetype)layoutWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    return [[[self alloc] initWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons] autorelease];
}

+ (instancetype)layoutWithLayout:(STKIconLayout *)layout
{
    return [[[self alloc] initWithLayout:layout] autorelease];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    NSMutableArray *topIcons = [NSMutableArray array];
    NSMutableArray *bottomIcons = [NSMutableArray array];
    NSMutableArray *leftIcons = [NSMutableArray array];
    NSMutableArray *rightIcons = [NSMutableArray array];

    SBIconModel *model = (SBIconModel *)[[objc_getClass("SBIconController") sharedInstance] model];
    
    MAP(dict[STKTopIconsKey], ^(NSString *ID) { 
        id icon = [model expectedIconForDisplayIdentifier:ID];
        if (icon) {
            [topIcons addObject:icon];
        }
    });
    MAP(dict[STKBottomIconsKey], ^(NSString *ID) { 
        id icon = [model expectedIconForDisplayIdentifier:ID];
        if (icon) {
            [bottomIcons addObject:icon];
        }
    });
    MAP(dict[STKLeftIconsKey], ^(NSString *ID) { 
        id icon = [model expectedIconForDisplayIdentifier:ID];
        if (icon) {
            [leftIcons addObject:icon];
        }
    });
    MAP(dict[STKRightIconsKey], ^(NSString *ID) { 
        id icon = [model expectedIconForDisplayIdentifier:ID];
        if (icon) {
            [rightIcons addObject:icon];
        }
    });
    return [self initWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons];
}

- (instancetype)initWithIconsAtTop:(NSArray *)topIcons bottom:(NSArray *)bottomIcons left:(NSArray *)leftIcons right:(NSArray *)rightIcons
{
    if ((self = [super init])) {
        _topIcons    = [topIcons mutableCopy];
        _bottomIcons = [bottomIcons mutableCopy];
        _leftIcons   = [leftIcons mutableCopy];
        _rightIcons  = [rightIcons mutableCopy];
    }
    return self;
}

- (instancetype)initWithLayout:(STKIconLayout *)layout
{
    if ((self = [super init])) {
        _topIcons = [layout.topIcons copy];
        _bottomIcons = [layout.bottomIcons copy];
        _leftIcons = [layout.leftIcons copy];
        _rightIcons = [layout.rightIcons copy];
    }
    return self;
}

- (void)dealloc
{
    [_topIcons release];
    [_bottomIcons release];
    [_leftIcons release];
    [_rightIcons release];

    _topIcons    = nil;
    _bottomIcons = nil;
    _leftIcons   = nil;
    _rightIcons  = nil;

    [super dealloc];
}

- (void)enumerateIconsUsingBlock:(void(^)(id, STKLayoutPosition))block
{
    for (STKLayoutPosition i = 1; i <= 4; i++) {
        NSArray *icons = [self iconsForPosition:i];
        for (id icon in icons) {
            block(icon, i);
        }
    }
}

- (void)enumerateIconsUsingBlockWithIndexes:(void(^)(id icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index))block
{
    for (STKLayoutPosition i = 1; i <= 4; i++) {
        NSArray *icons = [self iconsForPosition:i];
        [icons enumerateObjectsUsingBlock:^(id icon, NSUInteger idx, BOOL *stop) {
            block(icon, i, icons, idx);
        }];
    }
}

- (NSArray *)iconsForPosition:(STKLayoutPosition)position
{
    return ((position == STKLayoutPositionTop) ? self.topIcons : (position == STKLayoutPositionBottom) ? self.bottomIcons : (position == STKLayoutPositionLeft) ? self.leftIcons : self.rightIcons);
}

- (NSArray *)allIcons
{
    if (!_hasBeenModified && _allIcons) {
        goto ret;
    }

    [_allIcons release];
    _allIcons = nil;

    _allIcons = [[NSMutableArray alloc] initWithCapacity:self.totalIconCount];

    for (STKLayoutPosition i = 1; i <= 4; i++) {
        [(NSMutableArray *)_allIcons addObjectsFromArray:[self iconsForPosition:i]];
    }
    
ret:
    return [[_allIcons copy] autorelease];
}

- (NSUInteger)totalIconCount
{
    return (self.topIcons.count + self.bottomIcons.count + self.leftIcons.count + self.rightIcons.count);
}

- (void)addIcon:(SBIcon *)icon toIconsAtPosition:(STKLayoutPosition)position
{
    if (!icon || position < STKLayoutPositionTop || position > STKLayoutPositionRight) {
        return;
    }
    @synchronized(self) {
        [*[self _nonNilArrayForPosition:position] addObject:icon];
        _hasBeenModified = YES;
    }
}

- (void)setIcon:(id)icon atIndex:(NSUInteger)idx position:(STKLayoutPosition)position
{
    if (!icon || position < STKLayoutPositionTop || position > STKLayoutPositionRight) {
        return;
    }
    @synchronized(self) {
        NSMutableArray *icons = *[self _nonNilArrayForPosition:position];
        if (icons == NULL) {
            // The position is invalid
            return;
        }
        if (idx < [icons count]){
            [icons removeObjectAtIndex:idx];
            [icons insertObject:icon atIndex:idx];
        }
        else {
            [icons addObject:icon];
        }
       _hasBeenModified = YES;
    }
}

- (void)removeIcon:(id)icon fromIconsAtPosition:(STKLayoutPosition)position
{
    if (!icon || position < STKLayoutPositionTop || position > STKLayoutPositionRight) {
        return;
    }
    @synchronized(self) {
        NSMutableArray *array = (NSMutableArray *)[self iconsForPosition:position];
        [array removeObject:icon];
        _hasBeenModified = YES;
    }
}

- (void)removeIcon:(id)icon
{
    if (!icon) {
        return;
    }

    @synchronized(self) {
        for (STKLayoutPosition i = 1; i <= 4; i++) {
            [(NSMutableArray *)[self iconsForPosition:i] removeObject:icon];
        }

        _hasBeenModified = YES;
    }
}

- (void)removeAllIconsForPosition:(STKLayoutPosition)position
{
    @synchronized(self) {
        [(NSMutableArray *)[self iconsForPosition:position] removeAllObjects];
        _hasBeenModified = YES;
    }
}

- (void)removeAllIcons
{
    @synchronized(self) {
        for (STKLayoutPosition pos = 1; pos <= 4; pos++) {
            [self removeAllIconsForPosition:pos];
        }       

        [_topIcons release];
        _topIcons = nil;
        
        [_bottomIcons release];
        _bottomIcons = nil;
        
        [_leftIcons release];
        _leftIcons = nil;
        
        [_rightIcons release];
        _rightIcons = nil;
        
        _hasBeenModified = YES;
    }
}

- (void)removeIconAtIndex:(NSUInteger)idx fromIconsAtPosition:(STKLayoutPosition)position;
{
    @synchronized(self) {
        NSMutableArray *array = (NSMutableArray *)[self iconsForPosition:position];
        if (array.count > 0 && idx < array.count) {
            [array removeObjectAtIndex:idx];
        }
        else {
            STKLog(@"%s: Index %i is out of bounds of array at position: %i. Dying silently", __PRETTY_FUNCTION__, idx, position);
        }
        _hasBeenModified = YES;
    }
}

- (STKLayoutPosition)positionForIcon:(id)icon
{
    for (STKLayoutPosition i = 1; i <= 4; i++) {
        NSArray *icons = [self iconsForPosition:i];
        if ([icons containsObject:icon]) {
            return i;
        }
    }

    return NSNotFound;
}

- (void)getPosition:(STKLayoutPosition *)positionRef andIndex:(NSUInteger *)idxRef forIcon:(id)icon
{
    STKLayoutPosition pos = [self positionForIcon:icon];
    if (positionRef) {
        *positionRef = pos;
    }
    
    NSUInteger idx = [[self iconsForPosition:pos] indexOfObject:icon];
    if (idxRef) {
        *idxRef = idx;
    }
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len
{
    return [[self allIcons] countByEnumeratingWithState:state objects:stackbuf count:len];
}

- (NSDictionary *)dictionaryRepresentation
{
    if (_dictRepr && !_hasBeenModified) {
        return _dictRepr;
    }

    [_dictRepr release];
    _dictRepr = nil;
    _dictRepr = [[NSMutableDictionary alloc] initWithCapacity:4];

    if (_topIcons) {
        _dictRepr[STKTopIconsKey] = [_topIcons valueForKey:@"leafIdentifier"];
    }
    if (_bottomIcons) {
        _dictRepr[STKBottomIconsKey] = [_bottomIcons valueForKey:@"leafIdentifier"];
    }
    if (_leftIcons) {
        _dictRepr[STKLeftIconsKey] = [_leftIcons valueForKey:@"leafIdentifier"];
    }
    if (_rightIcons) {
        _dictRepr[STKRightIconsKey] = [_rightIcons valueForKey:@"leafIdentifier"];
    }

    return _dictRepr;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ top.count: %zd bottom.count: %zd left.count: %zd right.count: %zd", [super description], _topIcons.count, _bottomIcons.count, _leftIcons.count, _rightIcons.count];
}

- (NSMutableArray **)_nonNilArrayForPosition:(STKLayoutPosition)pos
{
    if (pos < STKLayoutPositionTop || pos > STKLayoutPositionRight) {
        return NULL;
    }
    
    NSMutableArray **array[4] = {&_topIcons, &_bottomIcons, &_leftIcons, &_rightIcons};
    pos -= 1;
    
    if (*(array[pos]) == nil) {
        *(array[pos]) = [NSMutableArray new];
    }
    return array[pos];
}

NSString * STKNSStringFromPosition(STKLayoutPosition pos)
{
    switch (pos) {
        case STKLayoutPositionTop:
            return @"STKLayoutPositionTop";
        case STKLayoutPositionBottom:
            return @"STKLayoutPositionBottom";
        case STKLayoutPositionLeft:
            return @"STKLayoutPositionLeft";
        case STKLayoutPositionRight:
            return @"STKLayoutPositionRight";
        default:
            return @"STKLayoutPositionNone";
    }
}

@end
