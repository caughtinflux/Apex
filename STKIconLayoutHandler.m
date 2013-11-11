#import "STKIconLayoutHandler.h"
#import "STKIconLayout.h"
#import "STKPlaceHolderIcon.h"

#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>
#import "SBIconListView+ApexAdditions.h"

#define kCurrentOrientation [UIApplication sharedApplication].statusBarOrientation


static SBIconListView *_centralIconListView;

@interface STKIconLayoutHandler ()

+ (STKIconLayout *)_processLayoutForSymmetry:(STKIconLayout *)layout withPosition:(STKPositionMask)position;

+ (NSArray *)_iconsAboveIcon:(SBIcon *)icon;
+ (NSArray *)_iconsBelowIcon:(SBIcon *)icon;
+ (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon;
+ (NSArray *)_iconsRightOfIcon:(SBIcon *)icon;
+ (NSArray *)_iconsInColumnWithX:(NSUInteger)x;
+ (NSArray *)_iconsInRowWithY:(NSUInteger)y;

+ (void)_logMask:(STKPositionMask)position;

@end

@implementation STKIconLayoutHandler

+ (STKIconLayout *)layoutForIcons:(NSArray *)icons aroundIconAtPosition:(STKPositionMask)position
{
    NSAssert((icons != nil), (@"*** -[STKIconLayoutHandler layoutForIcons:] cannot have a nil argument for icons"));

    if ((position & STKPositionDock) == STKPositionDock) {
        return [STKIconLayout layoutWithIconsAtTop:icons bottom:nil left:nil right:nil];
    }

    NSMutableArray *bottomIcons = [NSMutableArray array]; // 0 (Give bottom icons preference, since they're easier to tap with a downward swipe)
    NSMutableArray *topIcons    = [NSMutableArray array]; // 1
    NSMutableArray *leftIcons   = [NSMutableArray array]; // 2
    NSMutableArray *rightIcons  = [NSMutableArray array]; // 3

    if ((position & STKPositionDock) == STKPositionDock) {
        // Return all the icons in the array as icons to be displaced from the top.
        return [STKIconLayout layoutWithIconsAtTop:icons bottom:bottomIcons left:leftIcons right:rightIcons];
    }

    for (NSUInteger i = 0; i < icons.count; i++) {
        NSInteger layoutLocation = ((NSInteger)i % 4); // ALL THE MAGIC IS HERE. MATH IS AWESOME
        switch (layoutLocation) {
            case 0: {
                if (((position & STKPositionTouchingBottom) == STKPositionTouchingBottom)) {
                    [topIcons addObject:icons[i]];
                }
                else {
                    [bottomIcons addObject:icons[i]];
                }
                break;
            }

            case 1: {
                if ((position & STKPositionTouchingTop) == STKPositionTouchingTop) {
                    [bottomIcons addObject:icons[i]];
                }
                else {
                    [topIcons addObject:icons[i]];
                }
                break;
            }

            case 2: {
                if ((position & STKPositionTouchingLeft) == STKPositionTouchingLeft) {                    
                    [rightIcons addObject:icons[i]];
                }
                else {
                    [leftIcons addObject:icons[i]];
                }
                break;
            }

            case 3: {
                if ((position & STKPositionTouchingRight) == STKPositionTouchingRight) {
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
    
    return [self _processLayoutForSymmetry:[STKIconLayout layoutWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons] withPosition:position];
}

+ (BOOL)layout:(STKIconLayout *)layout requiresRelayoutForPosition:(STKPositionMask)position suggestedLayout:(__autoreleasing STKIconLayout **)outLayout
{
    if ((position & STKPositionDock) == STKPositionDock) {
        if (layout.leftIcons.count > 0 || layout.rightIcons.count > 0 || layout.bottomIcons.count > 0) {
            if (outLayout) {
                *outLayout = [self layoutForIcons:[layout allIcons] aroundIconAtPosition:position];
            }
            return YES;
        }
        return NO;
    }
    if ((position & STKPositionTouchingTop) == STKPositionTouchingTop) {
        if (layout.topIcons.count > 0) {
            return YES;
        }
    }
    if ((position & STKPositionTouchingBottom) == STKPositionTouchingBottom) {
        if (layout.bottomIcons.count > 0) {
            return YES;
        }
    }
    if ((position & STKPositionTouchingLeft) == STKPositionTouchingLeft) {
        if (layout.leftIcons.count > 0) {
            return YES;
        }
    }
    if ((position & STKPositionTouchingRight) == STKPositionTouchingRight) {
        if (layout.rightIcons.count > 0) {
            return YES;
        }
    }
    if (layout.topIcons.count > 1 || layout.bottomIcons.count > 1 || layout.leftIcons.count > 1 || layout.rightIcons.count > 1) {
        if (outLayout) {
            *outLayout = [self _processLayoutForSymmetry:layout withPosition:position];
        }
        return YES;
    }

    return NO;
}

+ (STKIconLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)centralIcon usingLayout:(STKIconLayout *)layout
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
    
    return [STKIconLayout layoutWithIconsAtTop:displacedTopIcons bottom:displacedBottomIcons left:displacedLeftIcons right:displacedRightIcons]; 
}


+ (STKIconCoordinates)coordinatesForIcon:(SBIcon *)icon withOrientation:(UIInterfaceOrientation)orientation
{
    _centralIconListView = STKListViewForIcon(icon);
    NSUInteger iconX = NSNotFound, iconY = NSNotFound;
    NSUInteger iconIndex = [[_centralIconListView icons] indexOfObject:icon]; 
    if (iconIndex != NSNotFound) {
        [_centralIconListView getX:&iconX Y:&iconY forIndex:iconIndex forOrientation:orientation];
    }
    return (STKIconCoordinates){iconX, iconY, iconIndex};
}

+ (STKIconLayout *)emptyLayoutForIconAtPosition:(STKPositionMask)position
{
    Class iconClass = objc_getClass("STKPlaceHolderIcon");
    NSArray *fullSizeStackArray = @[[[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease]];
    
    return [self layoutForIcons:fullSizeStackArray aroundIconAtPosition:position];
}

+ (STKIconLayout *)layoutForPlaceHoldersInLayout:(STKIconLayout *)layout withPosition:(STKPositionMask)position
{
    // Create an array with four objects to represent a full stack
    Class iconClass = objc_getClass("STKPlaceHolderIcon");
    NSArray *fullSizeStackArray = @[[[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease], [[iconClass new] autorelease]];

    // Get a layout object that represents how the icon would look with a full stack
    STKIconLayout *fullLayout = [self layoutForIcons:fullSizeStackArray aroundIconAtPosition:position];

    NSMutableArray *topIcons = [NSMutableArray array];
    NSMutableArray *bottomIcons = [NSMutableArray array];
    NSMutableArray *leftIcons = [NSMutableArray array];
    NSMutableArray *rightIcons = [NSMutableArray array];

    void(^addPlaceHoldersToArray)(NSMutableArray *array, NSInteger numPlaceHolders) = ^(NSMutableArray *array, NSInteger numPlaceHolders) {
        numPlaceHolders = MIN((position & STKPositionDock ? 4 : 2), numPlaceHolders); // A LA HAXX
        if (numPlaceHolders <= 0) { 
            return;
        }
        do {
            [array addObject:[[iconClass new] autorelease]];
        } while (--numPlaceHolders > 0);
    };

    if ((layout.topIcons == nil || layout.topIcons.count == 0 || layout.topIcons.count < fullLayout.topIcons.count) && !(position & STKPositionTouchingTop)) {
        addPlaceHoldersToArray(topIcons, (fullLayout.topIcons.count - layout.topIcons.count));
    }

    if ((layout.bottomIcons == nil || layout.bottomIcons.count == 0 || layout.bottomIcons.count < fullLayout.bottomIcons.count) && !(position & STKPositionTouchingBottom)) {
        addPlaceHoldersToArray(bottomIcons, (fullLayout.bottomIcons.count - layout.bottomIcons.count));
    }

    if ((layout.leftIcons == nil || layout.leftIcons.count == 0 || layout.leftIcons.count < fullLayout.leftIcons.count) && !(position & STKPositionTouchingLeft)) {
        addPlaceHoldersToArray(leftIcons, (fullLayout.leftIcons.count - layout.leftIcons.count));
    }

    if ((layout.rightIcons == nil || layout.rightIcons.count == 0 || layout.rightIcons.count < fullLayout.rightIcons.count) && !(position & STKPositionTouchingRight)) {
        addPlaceHoldersToArray(rightIcons, (fullLayout.rightIcons.count - layout.rightIcons.count));
    }

    STKIconLayout *placeHolderLayout = [STKIconLayout layoutWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons];
    placeHolderLayout.containsPlaceholders = YES;

    return placeHolderLayout;
}

+ (STKIconLayout *)_processLayoutForSymmetry:(STKIconLayout *)layout withPosition:(STKPositionMask)position
{
    NSMutableArray *topArray    = [layout.topIcons.mutableCopy autorelease] ?: [NSMutableArray array];
    NSMutableArray *bottomArray = [layout.bottomIcons.mutableCopy autorelease] ?: [NSMutableArray array];
    NSMutableArray *leftArray   = [layout.leftIcons.mutableCopy autorelease] ?: [NSMutableArray array];
    NSMutableArray *rightArray  = [layout.rightIcons.mutableCopy autorelease] ?: [NSMutableArray array];
    
    void (^processArray)(NSMutableArray *array) = ^(NSMutableArray *array) {
        if ((leftArray.count == 0) && !(position & STKPositionTouchingLeft)) {  
            [leftArray addObject:array[1]];
            [array removeObjectAtIndex:1];
        }
        else if ((rightArray.count == 0) && !(position & STKPositionTouchingRight)) {
            [rightArray addObject:array[1]]; 
            [array removeObjectAtIndex:1];
        }
        else if ((bottomArray.count == 0) && !(position & STKPositionTouchingBottom)) {
            [bottomArray addObject:array[1]];
            [array removeObjectAtIndex:1];
        }
        else if ((topArray.count == 0) && !(position & STKPositionTouchingTop)) {
            [topArray addObject:array[1]];
            [array removeObjectAtIndex:1];
        }
    };

    NSMutableArray *extraArray = nil;

    // Check for extras in the vertical positions   
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

    return [STKIconLayout layoutWithIconsAtTop:topArray bottom:bottomArray left:leftArray right:rightArray];
}

+ (NSArray *)_iconsAboveIcon:(SBIcon *)icon
{
    STKIconCoordinates coordinates = [self coordinatesForIcon:icon withOrientation:kCurrentOrientation];
    if (STKCoordinatesAreValid(coordinates) == NO) {
        return nil;
    }
    NSArray *ret = [[self _iconsInColumnWithX:coordinates.xPos] subarrayWithRange:NSMakeRange(0, coordinates.yPos)];
    return ret;
}

+ (NSArray *)_iconsBelowIcon:(SBIcon *)icon
{
    STKIconCoordinates coordinates = [self coordinatesForIcon:icon withOrientation:kCurrentOrientation];
    if (STKCoordinatesAreValid(coordinates) == NO) {
        return nil;
    }
    NSArray *iconsInColumn = [self _iconsInColumnWithX:coordinates.xPos];
    
    NSRange range;
    range.location = coordinates.yPos + 1;
    range.length = iconsInColumn.count - (coordinates.yPos + 1);

    return [iconsInColumn subarrayWithRange:range];
}

+ (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon
{
    STKIconCoordinates coordinates = [self coordinatesForIcon:icon withOrientation:kCurrentOrientation];
    if (STKCoordinatesAreValid(coordinates) == NO) {
        return nil;
    }
    NSArray *iconsInRow = [self _iconsInRowWithY:coordinates.yPos];
    
    NSRange range;
    range.location = 0;
    range.length = coordinates.xPos;

    return [iconsInRow subarrayWithRange:range];
}

+ (NSArray *)_iconsRightOfIcon:(SBIcon *)icon
{
    STKIconCoordinates coordinates = [self coordinatesForIcon:icon withOrientation:kCurrentOrientation];
    if (STKCoordinatesAreValid(coordinates) == NO) {
        return nil;
    }
    NSArray *iconsInRow = [self _iconsInRowWithY:coordinates.yPos];
    NSRange range;
    range.location = coordinates.xPos + 1;
    range.length = iconsInRow.count - (coordinates.xPos + 1);

    return [iconsInRow subarrayWithRange:range];
}

+ (NSArray *)_iconsInColumnWithX:(NSUInteger)x 
{
    NSMutableArray *icons = [NSMutableArray array];
    NSUInteger iconRows = [_centralIconListView stk_visibleIconRowsForCurrentOrientation];
    for (NSUInteger i = 0; i < iconRows; i++) {
        NSUInteger index = [_centralIconListView indexForX:x Y:i forOrientation:[UIApplication sharedApplication].statusBarOrientation];        
        if (index != NSNotFound && index < [_centralIconListView icons].count) {
            [icons addObject:[_centralIconListView icons][index]];
        }
    }
    return icons;
}

+ (NSArray *)_iconsInRowWithY:(NSUInteger)y
{
    NSMutableArray *icons = [NSMutableArray array];
    for (NSUInteger i = 0; i <= ([_centralIconListView stk_visibleIconColumnsForCurrentOrientation] - 1); i++) {
        NSUInteger index = [_centralIconListView indexForX:i Y:y forOrientation:[UIApplication sharedApplication].statusBarOrientation];
        if (index != NSNotFound && index < [_centralIconListView icons].count) {
            [icons addObject:[_centralIconListView icons][index]];
        }
    }
    return icons;
}

+ (void)_logMask:(STKPositionMask)position
{
    if (position & STKPositionTouchingTop) {
        CLog(@"STKPositionTouchingTop");
    }
    if (position & STKPositionTouchingBottom) {
        CLog(@"STKPositionTouchingBottom");
    }
    if (position & STKPositionTouchingLeft){
        CLog(@"STKPositionTouchingLeft");
    }
    if (position & STKPositionTouchingRight) {
        CLog(@"STKPositionTouchingRight");
    }
}

@end
