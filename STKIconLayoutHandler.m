#import "STKIconLayoutHandler.h"
#import "STKIconLayout.h"

@implementation STKIconLayoutHandler

- (STKIconLayout *)layoutForIcons:(NSArray *)icons
{
	NSAssert((icons != nil), (@"You must pass in a non-nil array to -[STKIconLayoutHandler layoutForIcons:]"));

	NSMutableArray *topIcons    = [NSMutableArray arrayWithCapacity:icons.count / 3.0]; // 0
	NSMutableArray *rightIcons  = [NSMutableArray arrayWithCapacity:icons.count / 3.0]; // 1
	NSMutableArray *bottomIcons = [NSMutableArray arrayWithCapacity:icons.count / 3.0]; // 2
	NSMutableArray *leftIcons   = [NSMutableArray arrayWithCapacity:icons.count / 3.0]; // 3

	for (NSUInteger i = 0; i <= icons.count; i++) {
		NSInteger layoutLocation = ((NSInteger)i % 4);
		switch (layoutLocation) {
			case 0:
				[topIcons addObject:icons[i]];
				break;

			case 1:
				[rightIcons addObject:icons[i]];
				break;

			case 2:
				[bottomIcons addObject:icons[i]];
				break;

			case 3:
				[leftIcons addObject:icons[i]];
				break;
		}
	}

	return [STKIconLayout layoutWithIconsAtTop:topIcons bottom:bottomIcons left:leftIcons right:rightIcons];
}

@end
