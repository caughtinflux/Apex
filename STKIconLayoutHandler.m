#import "STKIconLayoutHandler.h"
#import "STKIconLayout.h"
#import "STKPlaceHolderIcon.h"

#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>

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
    NSAssert((icons != nil), (@"You must pass in a non-nil array to -[STKIconLayoutHandler layoutForIcons:]"));

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

+ (STKIconLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)centralIcon usingLayout:(STKIconLayout *)layout
{
    NSArray *displacedTopIcons    = nil;
    NSArray *displacedBottomIcons = nil;
    NSArray *displacedLeftIcons   = nil;
    NSArray *displacedRightIcons  = nil;
    
    _centralIconListView = STKListViewForIcon(centralIcon);

    if (layout.topIcons) {
        displacedTopIcons = [self _iconsAboveIcon:centralIcon];
    }
    if (layout.bottomIcons) {
        displacedBottomIcons = [self _iconsBelowIcon:centralIcon];
    }
    if (layout.leftIcons) {
        displacedLeftIcons = [self _iconsLeftOfIcon:centralIcon];
    }
    if (layout.rightIcons) {
        displacedRightIcons = [self _iconsRightOfIcon:centralIcon];
    }

    _centralIconListView = nil;
    
    return [STKIconLayout layoutWithIconsAtTop:displacedTopIcons bottom:displacedBottomIcons left:displacedLeftIcons right:displacedRightIcons]; 
}

+ (STKIconCoordinates)coordinatesForIcon:(SBIcon *)icon withOrientation:(UIInterfaceOrientation)orientation
{
    _centralIconListView = STKListViewForIcon(icon);

    NSUInteger iconIndex, iconX, iconY;
    [_centralIconListView iconAtPoint:[_centralIconListView originForIcon:icon] index:&iconIndex];
    [_centralIconListView getX:&iconX Y:&iconY forIndex:iconIndex forOrientation:orientation];

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
    NSMutableArray *topArray = [layout.topIcons.mutableCopy autorelease];
    NSMutableArray *bottomArray = [layout.bottomIcons.mutableCopy autorelease];
    NSMutableArray *leftArray = [layout.leftIcons.mutableCopy autorelease];
    NSMutableArray *rightArray = [layout.rightIcons.mutableCopy autorelease];

    NSMutableArray *extraArray = nil;

    // Check for extras in the vertical positions   
    if (topArray.count > 1) {
        extraArray = topArray;
    }
    else if (bottomArray.count > 1) {
        extraArray = bottomArray;
    }

    if (extraArray) {
        if ((leftArray.count == 0) && !(position & STKPositionTouchingLeft)) {  
            [leftArray addObject:extraArray[1]];
            [extraArray removeObjectAtIndex:1];
        }
        else if ((rightArray.count == 0) && !(position & STKPositionTouchingRight)) {
            [rightArray addObject:extraArray[1]]; 
            [extraArray removeObjectAtIndex:1];
        }
    }


    extraArray = nil; // Set it back to nil for a pass at the horizontals

    if (leftArray.count > 1) {
        extraArray = leftArray;
    }
    else if (rightArray.count > 1) {
        extraArray = rightArray;
    }

    if (extraArray) {
        if ((topArray.count == 0) && !(position & STKPositionTouchingTop)) {
            [topArray addObject:extraArray[1]];
            [extraArray removeObjectAtIndex:1];
        }
        else if ((bottomArray.count == 0) && !(position & STKPositionTouchingBottom)) {
            [bottomArray addObject:extraArray[1]];
            [extraArray removeObjectAtIndex:1];
        }
    }

    return [STKIconLayout layoutWithIconsAtTop:topArray bottom:bottomArray left:leftArray right:rightArray];
}

+ (NSArray *)_iconsAboveIcon:(SBIcon *)icon
{
    STKIconCoordinates coordinates = [self coordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *ret = [[self _iconsInColumnWithX:coordinates.xPos] subarrayWithRange:NSMakeRange(0, coordinates.yPos)];
    return ret;
}

+ (NSArray *)_iconsBelowIcon:(SBIcon *)icon
{
    STKIconCoordinates coordinates = [self coordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *iconsInColumn = [self _iconsInColumnWithX:coordinates.xPos];
    
    NSRange range;
    range.location = coordinates.yPos + 1;
    range.length = iconsInColumn.count - (coordinates.yPos + 1);

    return [iconsInColumn subarrayWithRange:range];
}

+ (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon
{
    STKIconCoordinates coordinates = [self coordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *iconsInRow = [self _iconsInRowWithY:coordinates.yPos];
    
    NSRange range;
    range.location = 0;
    range.length = coordinates.xPos;

    return [iconsInRow subarrayWithRange:range];
}

+ (NSArray *)_iconsRightOfIcon:(SBIcon *)icon
{
    STKIconCoordinates coordinates = [self coordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *iconsInRow = [self _iconsInRowWithY:coordinates.yPos];
    
    NSRange range;
    range.location = coordinates.xPos + 1;
    range.length = iconsInRow.count - (coordinates.xPos + 1);

    return [iconsInRow subarrayWithRange:range];
}

+ (NSArray *)_iconsInColumnWithX:(NSUInteger)x 
{
    NSMutableArray *icons = [NSMutableArray array];
    for (NSUInteger i = 0; i <= ([_centralIconListView iconRowsForCurrentOrientation] - 1); i++) {
        NSUInteger index = [_centralIconListView indexForX:x Y:i forOrientation:[UIApplication sharedApplication].statusBarOrientation];
        if (index < [_centralIconListView icons].count) {
            [icons addObject:[_centralIconListView icons][index]];
        }
    }
    return icons;
}

+ (NSArray *)_iconsInRowWithY:(NSUInteger)y
{
    NSMutableArray *icons = [NSMutableArray array];
    for (NSUInteger i = 0; i <= ([_centralIconListView iconColumnsForCurrentOrientation] - 1); i++) {
        NSUInteger index = [_centralIconListView indexForX:i Y:y forOrientation:[UIApplication sharedApplication].statusBarOrientation];
        if (index < [_centralIconListView icons].count) {
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
