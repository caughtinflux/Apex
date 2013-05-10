#import <Foundation/Foundation.h>

@class SBIcon;
@interface STKPreferences : NSObject

@property (nonatomic, readonly) NSArray *identifiersForIconsWithStack;

+ (instancetype)sharedPreferences;

- (NSArray *)stackIconsForIcon:(SBIcon *)icon;
- (NSString *)layoutPathForIcon:(SBIcon *)icon;
- (void)reloadPreferences;
- (BOOL)iconHasStack:(SBIcon *)icon;

@end
