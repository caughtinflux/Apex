#import "STKIconLayoutHandler.h"
#import "STKIconLayout.h"

#import <objc/runtime.h>

#import <SpringBoard/SBIcon.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIconListView.h>
#import <SpringBoard/SBIconViewMap.h>
#import <SpringBoard/SBIconView.h>

#define kCurrentOrientation [UIApplication sharedApplication].statusBarOrientation

@interface STKIconLayoutHandler ()
{
    SBIconListView *_centralIconListView;
}

- (STKIconLayout *)_processLayoutForSymmetry:(STKIconLayout *)layout withPosition:(STKPositionMask)position;

- (NSArray *)_iconsAboveIcon:(SBIcon *)icon;
- (NSArray *)_iconsBelowIcon:(SBIcon *)icon;
- (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon;
- (NSArray *)_iconsRightOfIcon:(SBIcon *)icon;
- (NSArray *)_iconsInColumnWithX:(NSUInteger)x;
- (NSArray *)_iconsInRowWithY:(NSUInteger)y;

- (void)_logMask:(STKPositionMask)position;

@end

@implementation STKIconLayoutHandler
- (STKIconLayout *)layoutForIcons:(NSArray *)icons aroundIconAtPosition:(STKPositionMask)position
{
    NSAssert((icons != nil), (@"You must pass in a non-nil array to -[STKIconLayoutHandler layoutForIcons:]"));

    NSMutableArray *topIcons    = [NSMutableArray array]; // 0
    NSMutableArray *bottomIcons = [NSMutableArray array]; // 1
    NSMutableArray *leftIcons   = [NSMutableArray array]; // 2
    NSMutableArray *rightIcons  = [NSMutableArray array]; // 3

    [self _logMask:position];


    for (NSUInteger i = 0; i < icons.count; i++) {
        NSInteger layoutLocation = ((NSInteger)i % 4); // ALL THE MAGIC IS HERE. MATH IS AWESOME

        switch (layoutLocation) {
            case 0: {
                if ((position & STKPositionTouchingTop) == STKPositionTouchingTop) {
                    [bottomIcons addObject:icons[i]];
                }
                else {
                    [topIcons addObject:icons[i]];
                }
                break;
            }

            case 1: {
                if (((position & STKPositionTouchingBottom) == STKPositionTouchingBottom)  || ((position & STKPositionDock) == STKPositionDock)) {
                    if (((position & STKPositionTouchingTop) == STKPositionTouchingTop) && ((position & STKPositionTouchingRight) == STKPositionTouchingRight)) {
                        // BUGFIX
                        [bottomIcons addObject:icons[i]];
                    }
                    else {
                        [topIcons addObject:icons[i]];
                    }
                }
                else {
                    [bottomIcons addObject:icons[i]];
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
        }
    }
    
    return [self _processLayoutForSymmetry:[STKIconLayout layoutWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons] withPosition:position];
}

- (STKIconLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)centralIcon usingLayout:(STKIconLayout *)layout
{
    NSArray * __block displacedTopIcons    = nil;
    NSArray * __block displacedBottomIcons = nil;
    NSArray * __block displacedLeftIcons   = nil;
    NSArray * __block displacedRightIcons  = nil;
    
    _centralIconListView = STKListViewForIcon(centralIcon);

    [layout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
        switch (position) {
            case STKLayoutPositionTop:
                displacedTopIcons = [self _iconsAboveIcon:centralIcon];
                break;
            case STKLayoutPositionBottom:
                displacedBottomIcons = [self _iconsBelowIcon:centralIcon];
                break;
            case STKLayoutPositionLeft:
                displacedLeftIcons = [self _iconsLeftOfIcon:centralIcon];
                break;
            case STKLayoutPositionRight:
                displacedRightIcons = [self _iconsRightOfIcon:centralIcon];
                break;
        }
    }];

    STKIconLayout *displacedIconsLayout = [STKIconLayout layoutWithIconsAtTop:displacedTopIcons bottom:displacedBottomIcons left:displacedLeftIcons right:displacedRightIcons];
    return displacedIconsLayout;
}

- (STKIconCoordinates *)copyCoordinatesForIcon:(SBIcon *)icon withOrientation:(UIInterfaceOrientation)orientation
{
    SBIconListView *listView = STKListViewForIcon(icon);

    NSUInteger iconIndex, iconX, iconY;
    [listView iconAtPoint:[listView originForIcon:icon] index:&iconIndex];
    [listView getX:&iconX Y:&iconY forIndex:iconIndex forOrientation:orientation];

    STKIconCoordinates *coordinates = malloc(sizeof(STKIconCoordinates));
    coordinates->xPos = iconX;
    coordinates->yPos = iconY;
    coordinates->index = iconIndex;

    return coordinates;
}

- (STKIconLayout *)_processLayoutForSymmetry:(STKIconLayout *)layout withPosition:(STKPositionMask)position
{
    NSMutableArray *topArray = layout.topIcons.mutableCopy;
    NSMutableArray *bottomArray = layout.bottomIcons.mutableCopy;
    NSMutableArray *leftArray = layout.leftIcons.mutableCopy;
    NSMutableArray *rightArray = layout.rightIcons.mutableCopy;

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
            [rightArray addObject:layout.topIcons[1]]; 
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

- (NSArray *)_iconsAboveIcon:(SBIcon *)icon
{
    STKIconCoordinates *coordinates = [self copyCoordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *ret = [[self _iconsInColumnWithX:coordinates->xPos] subarrayWithRange:NSMakeRange(0, coordinates->yPos)];
    free(coordinates);
    return ret;
}

- (NSArray *)_iconsBelowIcon:(SBIcon *)icon
{
    STKIconCoordinates *coordinates = [self copyCoordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *iconsInColumn = [self _iconsInColumnWithX:coordinates->xPos];
    
    NSRange range;
    range.location = coordinates->yPos + 1;
    range.length = iconsInColumn.count - (coordinates->yPos + 1);

    free(coordinates);

    return [iconsInColumn subarrayWithRange:range];
}

- (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon
{
    STKIconCoordinates *coordinates = [self copyCoordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *iconsInRow = [self _iconsInRowWithY:coordinates->yPos];
    
    NSRange range;
    range.location = 0;
    range.length = coordinates->xPos;

    free(coordinates);

    return [iconsInRow subarrayWithRange:range];
}

- (NSArray *)_iconsRightOfIcon:(SBIcon *)icon
{
    STKIconCoordinates *coordinates = [self copyCoordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *iconsInRow = [self _iconsInRowWithY:coordinates->yPos];
    
    NSRange range;
    range.location = coordinates->xPos + 1;
    range.length = iconsInRow.count - (coordinates->xPos + 1);

    free(coordinates);

    return [iconsInRow subarrayWithRange:range];
}

- (NSArray *)_iconsInColumnWithX:(NSUInteger)x 
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

- (NSArray *)_iconsInRowWithY:(NSUInteger)y
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

- (void)_logMask:(STKPositionMask)position
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
