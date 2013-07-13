#import "STKPlaceHolderIcon.h"
#import "STKConstants.h"

#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

%subclass STKPlaceHolderIcon : SBIcon

- (NSString *)displayName
{
	return @"";
}

- (BOOL)allowsUninstall
{
	return NO;
}

- (UIImage *)getStandardIconImageForLocation:(NSInteger)location
{
	return [UIImage imageWithContentsOfFile:PATH_TO_IMAGE(@"EditingOverlay")];
}

%end
