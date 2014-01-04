#import "STKGroupLayoutHandler.h"
#import "STKGroupLayout.h"
#import "STKConstants.h"

#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>
#import "SBIconListView+ApexAdditions.h"

#define kCurrentOrientation [UIApplication sharedApplication].statusBarOrientation


static SBIconListView *_centralIconListView;

@interface STKGroupLayoutHandler ()

+ (STKGroupLayout *)_processLayoutForSymmetry:(STKGroupLayout *)layout withLocation:(STKLocation)location;

+ (NSArray *)_iconsAboveIcon:(SBIcon *)icon;
+ (NSArray *)_iconsBelowIcon:(SBIcon *)icon;
+ (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon;
+ (NSArray *)_iconsRightOfIcon:(SBIcon *)icon;
+ (NSArray *)_iconsInColumn:(NSInteger)column;
+ (NSArray *)_iconsInRow:(NSInteger)row;

+ (void)_logMask:(STKLocation)location;

@end

@implementation STKGroupLayoutHandler

+ (STKGroupLayout *)layoutForIcons:(NSArray *)icons aroundIconAtLocation:(STKLocation)location;
{
    NSAssert((icons != nil), (@"*** -[STKGroupLayoutHandler layoutForIcons:] cannot have a nil argument for icons"));

    if ((location & STKLocationDock) == STKLocationDock) {
        return [STKGroupLayout layoutWithIconsAtTop:icons bottom:nil left:nil right:nil];
    }
    [self _logMask:location];

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

+ (BOOL)layout:(STKGroupLayout *)layout requiresRelayoutForLocation:(STKLocation)location suggestedLayout:(__autoreleasing STKGroupLayout **)outLayout
{
    if ((location & STKLocationDock) == STKLocationDock) {
        if (layout.leftIcons.count > 0 || layout.rightIcons.count > 0 || layout.bottomIcons.count > 0) {
            if (outLayout) {
                *outLayout = [self layoutForIcons:[layout allIcons] aroundIconAtLocation:location];
            }
            return YES;
        }
        return NO;
    }
    if ((location & STKLocationTouchingTop) == STKLocationTouchingTop) {
        if (layout.topIcons.count > 0) {
            return YES;
        }
    }
    if ((location & STKLocationTouchingBottom) == STKLocationTouchingBottom) {
        if (layout.bottomIcons.count > 0) {
            return YES;
        }
    }
    if ((location & STKLocationTouchingLeft) == STKLocationTouchingLeft) {
        if (layout.leftIcons.count > 0) {
            return YES;
        }
    }
    if ((location & STKLocationTouchingRight) == STKLocationTouchingRight) {
        if (layout.rightIcons.count > 0) {
            return YES;
        }
    }
    if (layout.topIcons.count > 1 || layout.bottomIcons.count > 1 || layout.leftIcons.count > 1 || layout.rightIcons.count > 1) {
        if (outLayout) {
            *outLayout = [self _processLayoutForSymmetry:layout withLocation:location];
        }
        return YES;
    }

    return NO;
}

+ (STKGroupLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)centralIcon usingLayout:(STKGroupLayout *)layout
{
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


+ (SBIconCoordinate)coordinateForIcon:(SBIcon *)icon
{
    _centralIconListView = STKListViewForIcon(icon);
    return [_centralIconListView coordinateForIcon:icon];
}

+ (STKGroupLayout *)emptyLayoutForIconAtLocation:(STKLocation)location
{
    Class iconClass = objc_getClass("SBIcon");
    NSArray *fullSizeStackArray = @[[[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease]];
    
    return [self layoutForIcons:fullSizeStackArray aroundIconAtLocation:location];
}

+ (STKGroupLayout *)layoutForPlaceholdersInLayout:(STKGroupLayout *)layout withLocation:(STKLocation)location
{
    // Create an array with four objects to represent a full stack
    Class iconClass = objc_getClass("STKPlaceholderIcon");
    NSArray *fullSizeStackArray = @[[[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease]];

    // Get a layout object that represents how the icon would look with a full stack
    STKGroupLayout *fullLayout = [self layoutForIcons:fullSizeStackArray aroundIconAtLocation:location];

    NSMutableArray *topIcons = [NSMutableArray array];
    NSMutableArray *bottomIcons = [NSMutableArray array];
    NSMutableArray *leftIcons = [NSMutableArray array];
    NSMutableArray *rightIcons = [NSMutableArray array];

    void(^addPlaceHoldersToArray)(NSMutableArray *array, NSInteger numPlaceHolders) = ^(NSMutableArray *array, NSInteger numPlaceHolders) {
        numPlaceHolders = MIN((location & STKLocationDock ? 4 : 2), numPlaceHolders); // A LA HAXX
        if (numPlaceHolders <= 0) { 
            return;
        }
        do {
            [array addObject:[[iconClass new] autorelease]];
        } while (--numPlaceHolders > 0);
    };

    if ((layout.topIcons == nil || layout.topIcons.count == 0 || layout.topIcons.count < fullLayout.topIcons.count) && !(location & STKLocationTouchingTop)) {
        addPlaceHoldersToArray(topIcons, (fullLayout.topIcons.count - layout.topIcons.count));
    }

    if ((layout.bottomIcons == nil || layout.bottomIcons.count == 0 || layout.bottomIcons.count < fullLayout.bottomIcons.count) && !(location & STKLocationTouchingBottom)) {
        addPlaceHoldersToArray(bottomIcons, (fullLayout.bottomIcons.count - layout.bottomIcons.count));
    }

    if ((layout.leftIcons == nil || layout.leftIcons.count == 0 || layout.leftIcons.count < fullLayout.leftIcons.count) && !(location & STKLocationTouchingLeft)) {
        addPlaceHoldersToArray(leftIcons, (fullLayout.leftIcons.count - layout.leftIcons.count));
    }

    if ((layout.rightIcons == nil || layout.rightIcons.count == 0 || layout.rightIcons.count < fullLayout.rightIcons.count) && !(location & STKLocationTouchingRight)) {
        addPlaceHoldersToArray(rightIcons, (fullLayout.rightIcons.count - layout.rightIcons.count));
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
        if ((leftArray.count == 0) && !(location & STKLocationTouchingLeft)) {  
            [leftArray addObject:array[1]];
            [array removeObjectAtIndex:1];
        }
        else if ((rightArray.count == 0) && !(location & STKLocationTouchingRight)) {
            [rightArray addObject:array[1]]; 
            [array removeObjectAtIndex:1];
        }
        else if ((bottomArray.count == 0) && !(location & STKLocationTouchingBottom)) {
            [bottomArray addObject:array[1]];
            [array removeObjectAtIndex:1];
        }
        else if ((topArray.count == 0) && !(location & STKLocationTouchingTop)) {
            [topArray addObject:array[1]];
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
    if (STKCoordinateIsValid(coordinate) == NO) {
        return nil;
    }
    NSRange range;
    range.location = 0;
    range.length = (coordinate.row - 2);
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
    range.length = (coordinate.col - 2);

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

+ (void)_logMask:(STKLocation)location
{
    if (location & STKLocationTouchingTop) {
        CLog(@"STKLocationTouchingTop");
    }
    if (location & STKLocationTouchingBottom) {
        CLog(@"STKLocationTouchingBottom");
    }
    if (location & STKLocationTouchingLeft){
        CLog(@"STKLocationTouchingLeft");
    }
    if (location & STKLocationTouchingRight) {
        CLog(@"STKLocationTouchingRight");
    }
}

@end
