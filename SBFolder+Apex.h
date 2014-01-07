#import "STKConstants.h"
#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>

@interface SBFolder (Apex)

- (BOOL)isApexFolder;

- (SBIcon *)centralIconForApex;

- (void)convertToApexFolder;
- (void)convertToRegularFolder;

@end
