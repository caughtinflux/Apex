#import "STKPlaceholderIcon.h"
#import "STKConstants.h"

#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

%subclass STKPlaceholderIcon : SBIcon

- (NSString *)displayName
{
	return @"";
}

- (NSString *)leafIdentifier
{
	return STKPlaceholderIconIdentifier;
}

- (BOOL)allowsUninstall
{
	return NO;
}

- (BOOL)isPlaceholder
{
	return YES;
}

- (UIImage *)getStandardIconImageForLocation:(NSInteger)location
{
	return [UIImage imageWithContentsOfFile:PATH_TO_IMAGE(@"EditingOverlay")];
}

%end
