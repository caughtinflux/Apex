#import <Foundation/Foundation.h>

@class SBIcon;
@interface STKPreferences : NSObject

+ (instancetype)sharedPreferences;

@property (nonatomic, readonly) NSArray *identifiersForIconsWithStack;

- (NSArray *)stackIconsForIcon:(SBIcon *)icon;
- (NSString *)layoutPathForIcon:(SBIcon *)icon;
- (void)reloadPreferences;
- (BOOL)iconHasStack:(SBIcon *)icon;

@end
