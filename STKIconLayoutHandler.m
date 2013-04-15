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

- (NSArray *)_iconsAboveIcon:(SBIcon *)icon;
- (NSArray *)_iconsBelowIcon:(SBIcon *)icon;
- (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon;
- (NSArray *)_iconsRightOfIcon:(SBIcon *)icon;
- (NSArray *)_iconsInColumnWithX:(NSUInteger)x;
- (NSArray *)_iconsInRowWithY:(NSUInteger)y;

@end

@implementation STKIconLayoutHandler

- (STKIconLayout *)layoutForIcons:(NSArray *)icons aroundIconAtPosition:(NSUInteger)position
{
    NSAssert((icons != nil), (@"You must pass in a non-nil array to -[STKIconLayoutHandler layoutForIcons:]"));

    NSMutableArray *topIcons    = [NSMutableArray array]; // 0
    NSMutableArray *bottomIcons = [NSMutableArray array]; // 1
    NSMutableArray *leftIcons   = [NSMutableArray array]; // 2
    NSMutableArray *rightIcons  = [NSMutableArray array]; // 3

    for (NSUInteger i = 0; i < icons.count; i++) {
        NSInteger layoutLocation = ((NSInteger)i % 4); // ALL THE MAGIC IS HERE. MATH IS AWESOME

        switch (layoutLocation) {
            case 0: {
                if ((position & STKPositionTouchingTop) == STKPositionTouchingTop) {
                    DLog(@"No place at the top, reassign to bottom");
                    [bottomIcons addObject:icons[i]];
                }
                else {
                    [topIcons addObject:icons[i]];
                }
                break;
            }

            case 1: {
                if (((position & STKPositionTouchingBottom) == STKPositionTouchingBottom) || ((position & STKPositionDock) == STKPositionDock)) {
                    DLog(@"No place at the bottom, add to top");
                    [topIcons addObject:icons[i]];
                }
                else {
                    [bottomIcons addObject:icons[i]];
                }
                break;
            }

            case 2: {
                if ((position & STKPositionTouchingLeft) == STKPositionTouchingLeft) {
                    DLog(@"No place on the left, reassign to right");
                    [rightIcons addObject:icons[i]];
                }
                else {
                    [leftIcons addObject:icons[i]];
                }
                break;
            }

            case 3: {
                if ((position & STKPositionTouchingRight) == STKPositionTouchingRight) {
                    DLog(@"No place on the right, reassign to left");
                    [leftIcons addObject:icons[i]];
                }
                else {
                    [rightIcons addObject:icons[i]];
                }
                break;
            }
        }
    }

    return [STKIconLayout layoutWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons];
}

- (STKIconLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)centralIcon usingLayout:(STKIconLayout *)layout;
{
    NSArray * __block displacedTopIcons    = nil;
    NSArray * __block displacedBottomIcons = nil;
    NSArray * __block displacedLeftIcons   = nil;
    NSArray * __block displacedRightIcons  = nil;
    
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
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];

    NSUInteger iconIndex, iconX, iconY;
    [listView iconAtPoint:[listView originForIcon:icon] index:&iconIndex];
    [listView getX:&iconX Y:&iconY forIndex:iconIndex forOrientation:orientation];

    STKIconCoordinates *coordinates = malloc(sizeof(STKIconCoordinates));
    coordinates->xPos = iconX;
    coordinates->yPos = iconY;
    coordinates->index = iconIndex;

    return coordinates;
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

    return [iconsInColumn subarrayWithRange:range];
}

- (NSArray *)_iconsLeftOfIcon:(SBIcon *)icon
{
    STKIconCoordinates *coordinates = [self copyCoordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *iconsInRow = [self _iconsInRowWithY:coordinates->yPos];
    
    NSRange range;
    range.location = 0;
    range.length = coordinates->xPos;

    return [iconsInRow subarrayWithRange:range];
}

- (NSArray *)_iconsRightOfIcon:(SBIcon *)icon
{
    STKIconCoordinates *coordinates = [self copyCoordinatesForIcon:icon withOrientation:kCurrentOrientation];
    NSArray *iconsInRow = [self _iconsInRowWithY:coordinates->yPos];
    
    NSRange range;
    range.location = coordinates->xPos + 1;
    range.length = iconsInRow.count - (coordinates->xPos + 1);

    return [iconsInRow subarrayWithRange:range];
}

- (NSArray *)_iconsInColumnWithX:(NSUInteger)x 
{
    NSMutableArray *icons = [NSMutableArray array];
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];
    for (NSUInteger i = 0; i <= ([listView iconRowsForCurrentOrientation] - 1); i++) {
        SBIcon *icon = [listView icons][([listView indexForX:x Y:i forOrientation:[UIApplication sharedApplication].statusBarOrientation])];
        [icons addObject:icon];
    }
    return icons;
}

- (NSArray *)_iconsInRowWithY:(NSUInteger)y
{
    NSMutableArray *icons = [NSMutableArray array];
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];
    for (NSUInteger i = 0; i <= ([listView iconColumnsForCurrentOrientation] - 1); i++) {
        SBIcon *icon = [listView icons][([listView indexForX:i Y:y forOrientation:[UIApplication sharedApplication].statusBarOrientation])];
        [icons addObject:icon];
    }
    return icons;
}

@end
