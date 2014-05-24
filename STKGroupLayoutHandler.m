#import "STKGroupLayoutHandler.h"
#import "STKConstants.h"

#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>


#define kCurrentOrientation [UIApplication sharedApplication].statusBarOrientation
#define COORD_IS_INVALID(_coord) (_coord.row == 0 || _coord.col == 0 || _coord.row == NSNotFound || _coord.col == NSNotFound)

static SBIconListView *_centralIconListView;

@interface STKGroupLayoutHandler ()

+ (STKGroupLayout *)_processLayoutForSymmetry:(STKGroupLayout *)layout withLocation:(STKLocation)location;

+ (NSArray *)_iconsAboveIcon:(SBIcon *)icon;
+ (NSArray *)_iconsBelowIcon:(SBIcon *)icon;
+ (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon;
+ (NSArray *)_iconsRightOfIcon:(SBIcon *)icon;
+ (NSArray *)_iconsInColumn:(NSInteger)column;
+ (NSArray *)_iconsInRow:(NSInteger)row;

@end

@implementation STKGroupLayoutHandler

+ (STKGroupLayout *)layoutForIcons:(NSArray *)icons aroundIconAtLocation:(STKLocation)location;
{
    NSAssert((icons != nil), (@"*** -[STKGroupLayoutHandler layoutForIcons:] cannot have a nil argument for icons"));

    if ((location & STKLocationDock) == STKLocationDock) {
        return [STKGroupLayout layoutWithIconsAtTop:icons bottom:nil left:nil right:nil];
    }

    NSMutableArray *bottomIcons = [NSMutableArray array]; // 0 (Give bottom icons preference, since they're easier to tap with a downward swipe)
    NSMutableArray *topIcons    = [NSMutableArray array]; // 1
    NSMutableArray *leftIcons   = [NSMutableArray array]; // 2
    NSMutableArray *rightIcons  = [NSMutableArray array]; // 3

    if ((location & STKLocationDock) == STKLocationDock) {
        // Return all the icons in the array as icons to be displaced from the top.
        return [STKGroupLayout layoutWithIconsAtTop:icons bottom:bottomIcons left:leftIcons right:rightIcons];
    }

    for (NSUInteger i = 0; i < icons.count; i++) {
        NSInteger layoutLocation = ((NSInteger)i % 4); // ALL THE MAGIC IS HERE. MATH IS AWESOME
        switch (layoutLocation) {
            case 0: {
                if (((location & STKLocationTouchingBottom) == STKLocationTouchingBottom)) {
                    [topIcons addObject:icons[i]];
                }
                else {
                    [bottomIcons addObject:icons[i]];
                }
                break;
            }
            case 1: {
                if ((location & STKLocationTouchingTop) == STKLocationTouchingTop) {
                    [bottomIcons addObject:icons[i]];
                }
                else {
                    [topIcons addObject:icons[i]];
                }
                break;
            }
            case 2: {
                if ((location & STKLocationTouchingLeft) == STKLocationTouchingLeft) {                    
                    [rightIcons addObject:icons[i]];
                }
                else {
                    [leftIcons addObject:icons[i]];
                }
                break;
            }
            case 3: {
                if ((location & STKLocationTouchingRight) == STKLocationTouchingRight) {
                    [leftIcons addObject:icons[i]];
                }
                else {
                    [rightIcons addObject:icons[i]];
                }
                break;
            }
            default: {
                break;
            }
        }
    }
    
    return [self _processLayoutForSymmetry:[STKGroupLayout layoutWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons] withLocation:location];
}

+ (STKGroupLayout *)correctLayoutForGroupIfNecessary:(STKGroup *)group
{
    NSParameterAssert(group.centralIcon);
    STKLocation location = [self locationForIcon:group.centralIcon];
    STKGroupLayout *layout = group.layout;
    BOOL requiresRelayout = NO;
    STKGroupLayout *retLayout = nil;
    if ((location & STKLocationDock) == STKLocationDock) {
        if (layout.leftIcons.count > 0 || layout.rightIcons.count > 0 || layout.bottomIcons.count > 0) {
            retLayout = [self layoutForIcons:[layout allIcons] aroundIconAtLocation:location];   
        }
    }
    else {
        requiresRelayout = (((location & STKLocationTouchingTop) && layout.topIcons.count > 0)
                            || ((location & STKLocationTouchingBottom) && layout.bottomIcons.count > 0)
                            || ((location & STKLocationTouchingLeft) && layout.leftIcons.count > 0)
                            || ((location & STKLocationTouchingRight) && layout.rightIcons.count > 0));
        if (requiresRelayout) {
            retLayout = [self layoutForIcons:[group.layout allIcons] aroundIconAtLocation:location];
        }
        else if (layout.topIcons.count > 1 || layout.bottomIcons.count > 1 || layout.leftIcons.count > 1 || layout.rightIcons.count > 1) {
            retLayout = [self _processLayoutForSymmetry:layout withLocation:location];
        }
    }
    return retLayout;
}

+ (STKGroupLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)centralIcon usingLayout:(STKGroupLayout *)layout
{
    if (COORD_IS_INVALID([self coordinateForIcon:centralIcon])) {
        return nil;
    }
    NSArray *displacedTopIcons    = nil;
    NSArray *displacedBottomIcons = nil;
    NSArray *displacedLeftIcons   = nil;
    NSArray *displacedRightIcons  = nil;

    _centralIconListView = STKListViewForIcon(centralIcon);

    if (layout.topIcons.count > 0) {
        displacedTopIcons = [self _iconsAboveIcon:centralIcon];
    }
    if (layout.bottomIcons.count > 0) {
        displacedBottomIcons = [self _iconsBelowIcon:centralIcon];
    }
    if (layout.leftIcons.count > 0) {
        displacedLeftIcons = [self _iconsLeftOfIcon:centralIcon];
    }
    if (layout.rightIcons.count > 0) {
        displacedRightIcons = [self _iconsRightOfIcon:centralIcon];
    }
    _centralIconListView = nil;

    return [STKGroupLayout layoutWithIconsAtTop:displacedTopIcons bottom:displacedBottomIcons left:displacedLeftIcons right:displacedRightIcons]; 
}

+ (STKGroupLayout *)layoutForIconsToHideAboveDockedIcon:(SBIcon *)centralIcon
                                            usingLayout:(STKGroupLayout *)layout
                                    targetFrameProvider:(CGRect(^)(NSUInteger idx))provider;
{
    NSParameterAssert(provider);
    if (layout.topIcons.count == 0) {
        return nil;
    }
    SBIconListView *rootListView = [[CLASS(SBIconController) sharedInstance] currentRootIconList];
    STKGroupLayout *displacedLayout = [[[STKGroupLayout alloc] init] autorelease];
    NSUInteger idx = 0;
    while (idx < [layout allIcons].count) {
        CGRect targetFrame = provider(idx);
        for (SBIcon *icon in [rootListView icons]) {
            SBIconView *iv = [rootListView viewForIcon:icon];
            if (CGRectIntersectsRect(targetFrame, iv.frame) && iv) {
                [displacedLayout addIcon:iv.icon toIconsAtPosition:STKPositionTop];
            }
        }
        idx++;
    }
    return displacedLayout;
}

+ (SBIconCoordinate)coordinateForIcon:(SBIcon *)icon
{
    SBIconListView *iconListView = STKListViewForIcon(icon);
    NSUInteger idx = [[iconListView model] indexForLeafIconWithIdentifier:icon.leafIdentifier];
    return [iconListView coordinateForIconAtIndex:idx];
}

+ (STKLocation)locationForIcon:(SBIcon *)icon
{
    STKLocation location = 0x0;
    SBIconListView *listView = STKListViewForIcon(icon);
    if ([[listView viewForIcon:icon] isInDock]) {
        return (location | STKLocationDock);
    }
    SBIconCoordinate coordinate = [STKGroupLayoutHandler coordinateForIcon:icon];
    
    if (coordinate.col == 1) {
        location |= STKLocationTouchingLeft;
    }
    if (coordinate.col == ([listView iconColumnsForCurrentOrientation])) {
        location |= STKLocationTouchingRight;
    }
    if (coordinate.row == 1) {
        location |= STKLocationTouchingTop;
    }
    if (coordinate.row == ([listView iconRowsForCurrentOrientation])) {
        location |= STKLocationTouchingBottom;
    }

    return location;
}

+ (STKGroupLayout *)emptyLayoutForIconAtLocation:(STKLocation)location
{
    Class iconClass = objc_getClass("STKEmptyIcon");
    NSArray *fullSizeGroupArray = @[[[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease]];
    return [self layoutForIcons:fullSizeGroupArray aroundIconAtLocation:location];
}

+ (STKGroupLayout *)placeholderLayoutForGroup:(STKGroup *)group
{
    // Create an array with four objects to represent a full group
    Class iconClass = CLASS(STKPlaceholderIcon);
    SBIcon *placeholderIcon = [[iconClass new] autorelease];
    NSArray *fullSizeGroupArray = @[placeholderIcon, placeholderIcon, placeholderIcon, placeholderIcon];
    STKLocation location = [self locationForIcon:group.centralIcon];
    STKGroupLayout *layout = group.layout;
    // Get a layout object that represents how the icon would look with a full stack
    STKGroupLayout *fullLayout = [self layoutForIcons:fullSizeGroupArray aroundIconAtLocation:location];

    NSMutableArray *topIcons = [NSMutableArray array];
    NSMutableArray *bottomIcons = [NSMutableArray array];
    NSMutableArray *leftIcons = [NSMutableArray array];
    NSMutableArray *rightIcons = [NSMutableArray array];

    NSUInteger topCount = layout.topIcons.count;
    NSUInteger bottomCount = layout.bottomIcons.count;
    NSUInteger leftCount = layout.leftIcons.count;
    NSUInteger rightCount = layout.rightIcons.count;

    void(^addPlaceHoldersToArray)(NSMutableArray *array, NSInteger numPlaceHolders) = ^(NSMutableArray *array, NSInteger numPlaceHolders) {
        numPlaceHolders = MIN((location & STKLocationDock ? 4 : 2), numPlaceHolders); // A LA HAXX
        if (numPlaceHolders <= 0) { 
            return;
        }
        do {
            [array addObject:[[iconClass new] autorelease]];
        } while (--numPlaceHolders > 0);
    };

    if ((layout.topIcons == nil || topCount == 0 || topCount < fullLayout.topIcons.count) && !(location & STKLocationTouchingTop)) {
        addPlaceHoldersToArray(topIcons, (fullLayout.topIcons.count - topCount));
    }

    if ((layout.bottomIcons == nil || bottomCount == 0 || bottomCount < fullLayout.bottomIcons.count) && !(location & STKLocationTouchingBottom)) {
        addPlaceHoldersToArray(bottomIcons, (fullLayout.bottomIcons.count - bottomCount));
    }

    if ((layout.leftIcons == nil || leftCount == 0 || leftCount < fullLayout.leftIcons.count) && !(location & STKLocationTouchingLeft)) {
        addPlaceHoldersToArray(leftIcons, (fullLayout.leftIcons.count - leftCount));
    }

    if ((layout.rightIcons == nil || rightCount == 0 || rightCount < fullLayout.rightIcons.count) && !(location & STKLocationTouchingRight)) {
        addPlaceHoldersToArray(rightIcons, (fullLayout.rightIcons.count - rightCount));
    }

    STKGroupLayout *placeHolderLayout = [STKGroupLayout layoutWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons];

    return placeHolderLayout;
}

+ (STKGroupLayout *)_processLayoutForSymmetry:(STKGroupLayout *)layout withLocation:(STKLocation)location
{
    NSMutableArray *topArray    = [layout.topIcons.mutableCopy autorelease] ?: [NSMutableArray array];
    NSMutableArray *bottomArray = [layout.bottomIcons.mutableCopy autorelease] ?: [NSMutableArray array];
    NSMutableArray *leftArray   = [layout.leftIcons.mutableCopy autorelease] ?: [NSMutableArray array];
    NSMutableArray *rightArray  = [layout.rightIcons.mutableCopy autorelease] ?: [NSMutableArray array];

    
    void (^processArray)(NSMutableArray *array) = ^(NSMutableArray *array) {
        id arrayToAddIcon = nil;
        if ((leftArray.count == 0 && !(location & STKLocationTouchingLeft))
         || (leftArray.count == 1 && (location & STKLocationTouchingRight))) {  
            arrayToAddIcon = leftArray;
        }
        else if ((rightArray.count == 0 && !(location & STKLocationTouchingRight))
              || (rightArray.count == 1 && (location & STKLocationTouchingLeft))) {
            arrayToAddIcon = rightArray;
        }
        else if ((bottomArray.count == 0 && !(location & STKLocationTouchingBottom))
              || (bottomArray.count == 1 &&  (location & STKLocationTouchingTop))) {
            arrayToAddIcon = bottomArray;
        }
        else if ((topArray.count == 0 && !(location & STKLocationTouchingTop))
              || (topArray.count == 1 &&  (location & STKLocationTouchingBottom))) {
            arrayToAddIcon = topArray;
        }
        
        if (arrayToAddIcon) {
            [arrayToAddIcon addObject:array[1]];
            [array removeObjectAtIndex:1];
        }
    };

    NSMutableArray *extraArray = nil;

    // Check for extras in the vertical locations   
    if (topArray.count > 1) {
        extraArray = topArray;
    }
    else if (bottomArray.count > 1) {
        extraArray = bottomArray;
    }
    if (extraArray) processArray(extraArray);

    extraArray = nil; // Set it back to nil for a pass at the horizontals

    if (leftArray.count > 1) {
        extraArray = leftArray;
    }
    else if (rightArray.count > 1) {
        extraArray = rightArray;
    }
    if (extraArray) processArray(extraArray);

    return [STKGroupLayout layoutWithIconsAtTop:topArray bottom:bottomArray left:leftArray right:rightArray];
}

+ (NSArray *)_iconsAboveIcon:(SBIcon *)icon
{
    SBIconCoordinate coordinate = [self coordinateForIcon:icon];
    
    NSRange range;
    range.location = 0;
    range.length = (coordinate.row - 1);
    NSArray *iconsInColumn = [self _iconsInColumn:coordinate.col];
    return [[[iconsInColumn subarrayWithRange:range] reverseObjectEnumerator] allObjects];
}

+ (NSArray *)_iconsBelowIcon:(SBIcon *)icon
{
    SBIconCoordinate coordinate = [self coordinateForIcon:icon];
    if (STKCoordinateIsValid(coordinate) == NO) {
        return nil;
    }
    NSArray *iconsInColumn = [self _iconsInColumn:coordinate.col];
    
    NSRange range;
    range.location = coordinate.row;
    range.length = (iconsInColumn.count - coordinate.row);
    return [iconsInColumn subarrayWithRange:range];
}

+ (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon
{
    SBIconCoordinate coordinate = [self coordinateForIcon:icon];
    if (STKCoordinateIsValid(coordinate) == NO) {
        return nil;
    }
    NSArray *iconsInRow = [self _iconsInRow:coordinate.row];
    
    NSRange range;
    range.location = 0;
    range.length = (coordinate.col - 1);

    return [[[iconsInRow subarrayWithRange:range] reverseObjectEnumerator] allObjects];
}

+ (NSArray *)_iconsRightOfIcon:(SBIcon *)icon
{
    SBIconCoordinate coordinate = [self coordinateForIcon:icon];
    if (STKCoordinateIsValid(coordinate) == NO) {
        return nil;
    }
    NSArray *iconsInRow = [self _iconsInRow:coordinate.row];
    NSRange range;
    range.location = coordinate.col;
    range.length = (iconsInRow.count - coordinate.col);

    return [iconsInRow subarrayWithRange:range];
}

+ (NSArray *)_iconsInColumn:(NSInteger)col
{
    NSMutableArray *icons = [NSMutableArray array];
    NSUInteger iconRows = [_centralIconListView stk_visibleIconRowsForCurrentOrientation];
    for (NSUInteger i = 1; i <= iconRows; i++) {
        NSUInteger index = [_centralIconListView indexForCoordinate:(SBIconCoordinate){i, col} forOrientation:kCurrentOrientation];
        if (index != NSNotFound && index < [_centralIconListView icons].count) {
            [icons addObject:[_centralIconListView icons][index]];
        }
    }
    return icons;
}

+ (NSArray *)_iconsInRow:(NSInteger)row
{
    NSMutableArray *icons = [NSMutableArray array];
    for (NSUInteger i = 1; i <= [_centralIconListView stk_visibleIconColumnsForCurrentOrientation]; i++) {
        NSUInteger index = [_centralIconListView indexForCoordinate:(SBIconCoordinate){row, i} forOrientation:kCurrentOrientation];
        if (index != NSNotFound && index < [_centralIconListView icons].count) {
            [icons addObject:[_centralIconListView icons][index]];
        }
    }
    return icons;
}

@end
