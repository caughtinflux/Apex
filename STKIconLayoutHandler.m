#import "STKIconLayoutHandler.h"
#import "STKIconLayout.h"

#import <objc/runtime.h>

#import <SpringBoard/SBIcon.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIconListView.h>
#import <SpringBoard/SBIconViewMap.h>
#import <SpringBoard/SBIconView.h>

@interface STKIconLayoutHandler ()
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

- (STKIconLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)icon usingLayout:(STKIconLayout *)layout;
{
    // Now, STKIconLayout's arrays do ***not*** have more than two icons.
    // In this case, `layout` contains the apps that will appear.
    // We have to return the icons that have to make way for the ones in `layout`.
    SBIconListView *listView = [[objc_getClass("SBIconController") sharedInstance] currentRootIconList];    
    
    NSMutableArray *displacedTopIcons    = [NSMutableArray array];
    NSMutableArray *displacedBottomIcons = [NSMutableArray array];
    NSMutableArray *displacedLeftIcons   = [NSMutableArray array];
    NSMutableArray *displacedRightIcons  = [NSMutableArray array];

    STKIconCoordinates *coordinates = [self copyCoordinatesForIcon:icon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    DLog(@"coordinates for main icon: x: %i y: %i index: %i", coordinates->xPos, coordinates->yPos, coordinates->index);
    for (SBIcon *icon in layout.topIcons) {
        // Explanation:
        // Here, the magic is in the Y: argument. The Y position of the icon will be the yPos of the central icon - (index of `icon` + 1)
        // For example:
        // If index: 0 and yPos == 2, then the Y coordinate of the icon to be moved should be 1. Hence, the formula becomes (2 - (0 + 1)) == 1
        // Simple :P
        NSUInteger iconIndex = [listView indexForX:coordinates->xPos Y:(coordinates->yPos - ([layout.topIcons indexOfObject:icon] + 1)) forOrientation:[UIApplication sharedApplication].statusBarOrientation];
        if ((iconIndex < [listView icons].count) && (iconIndex != NSNotFound)) {
            [displacedTopIcons addObject:[listView icons][iconIndex]];
        }
    }
    // Similarly...
    for (SBIcon *icon in layout.bottomIcons) {
        NSUInteger iconIndex = [listView indexForX:coordinates->xPos Y:(coordinates->yPos + ([layout.bottomIcons indexOfObject:icon] + 1)) forOrientation:[UIApplication sharedApplication].statusBarOrientation];
        if ((iconIndex < [listView icons].count) && (iconIndex != NSNotFound)) {
            [displacedBottomIcons addObject:[listView icons][iconIndex]];
        }
    }

    for (SBIcon *icon in layout.leftIcons) {
        NSUInteger iconIndex = [listView indexForX:(coordinates->xPos - ([layout.leftIcons indexOfObject:icon] + 1)) Y:coordinates->yPos forOrientation:[UIApplication sharedApplication].statusBarOrientation];
        if ((iconIndex < [listView icons].count) && (iconIndex != NSNotFound)) {
            [displacedLeftIcons addObject:[listView icons][iconIndex]];
        }
    }
    
    for (SBIcon *icon in layout.rightIcons) {
        NSUInteger iconIndex = [listView indexForX:(coordinates->xPos + ([layout.rightIcons indexOfObject:icon] + 1)) Y:coordinates->yPos forOrientation:[UIApplication sharedApplication].statusBarOrientation];
        if ((iconIndex < [listView icons].count) && (iconIndex != NSNotFound)) {
            [displacedRightIcons addObject:[listView icons][iconIndex]];
        }
    }

    free(coordinates);

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

@end
