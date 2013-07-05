#import <Foundation/Foundation.h>

@class SBIcon;
@interface STKPreferences : NSObject

+ (instancetype)sharedPreferences;

- (void)reloadPreferences;

- (NSSet *)identifiersForIconsWithStack;
- (NSArray *)stackIconsForIcon:(SBIcon *)icon;

- (NSString *)layoutPathForIconID:(NSString *)iconID;
- (NSString *)layoutPathForIcon:(SBIcon *)icon;


- (BOOL)iconHasStack:(SBIcon *)icon;
- (BOOL)iconIsInStack:(SBIcon *)icon;

// icon: The central(visible) icon in the stack
// icons: NSArray of SBIcon objects that will be in the stack
// Returns: YES if the write completed successfully, else NO
- (BOOL)saveLayoutWithCentralIcon:(SBIcon *)icon stackIcons:(NSArray *)icons;

- (BOOL)saveLayoutWithCentralIconID:(NSString *)iconID stackIconIDs:(NSArray *)stackIconIDs;

@end
