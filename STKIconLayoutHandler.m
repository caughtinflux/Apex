#import "STKIconLayoutHandler.h"
#import "STKIconLayout.h"

@implementation STKIconLayoutHandler

- (STKIconLayout *)layoutForIcons:(NSArray *)icons
{
    NSAssert((icons != nil), (@"You must pass in a non-nil array to -[STKIconLayoutHandler layoutForIcons:]"));

    NSMutableArray *topIcons    = [NSMutableArray array]; // 0
    NSMutableArray *bottomIcons = [NSMutableArray array]; // 1
    NSMutableArray *leftIcons   = [NSMutableArray array]; // 2
    NSMutableArray *rightIcons  = [NSMutableArray array]; // 3

    for (NSUInteger i = 0; i < icons.count; i++) {
        NSInteger layoutLocation = ((NSInteger)i % 4); // ALL THE MAGIC IS HERE. MATH IS AWESOME
        switch (layoutLocation) {
            case 0:
                [topIcons addObject:icons[i]];
                break;

            case 1:
                [bottomIcons addObject:icons[i]];
                break;

            case 2:
                [leftIcons addObject:icons[i]];
                break;

            case 3:
                [rightIcons addObject:icons[i]];
                break;
        }
    }

    return [STKIconLayout layoutWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons];
}

@end
