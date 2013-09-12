#import <Foundation/Foundation.h>
#import "Globals.h"

@interface STKPrefsHelper : NSObject
{
@private
    NSBundle *ownBundle;
}

+ (instancetype)sharedHelper;
- (UIImage *)ownImageNamed:(NSString *)name;
- (NSString *)ownStringForKey:(NSString *)key;
- (NSBundle *)ownBundle;

@end
