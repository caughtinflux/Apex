#import <Foundation/Foundation.h>

@class SBIcon;
@interface STKPreferences : NSObject

+ (instancetype)sharedPreferences;

@property (nonatomic, readonly) NSArray *identifiersForIconsWithStack;

- (NSArray *)stackIconsForIcon:(SBIcon *)icon;
- (NSString *)layoutPathForIcon:(SBIcon *)icon;
- (void)reloadPreferences;
- (BOOL)iconHasStack:(SBIcon *)icon;

// icon: The central(visible) icon in the stack
// icons: NSArray of SBIcon objects that will be in the stack
// Returns: YES if the write completed successfully, else NO
- (BOOL)createLayoutWithCentralIcon:(SBIcon *)icon stackIcons:(NSArray *)icons;

@end
