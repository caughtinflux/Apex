#import <Foundation/Foundation.h>

typedef void(^STKPreferencesCallbackBlock)(void);

@class SBIcon;
@interface STKPreferences : NSObject

+ (NSString *)layoutsDirectory;

+ (instancetype)sharedPreferences;

- (void)reloadPreferences;

@property (nonatomic, readonly) NSArray *identifiersForIconsInStacks;
@property (nonatomic, assign) BOOL previewEnabled;

- (NSSet *)identifiersForIconsWithStack;
- (NSArray *)stackIconsForIcon:(SBIcon *)icon;

// Pass in a NSString for `icon`, you get an NSString in return
// If `icon` is a SBIcon instance, you get a SBIcon in return!
- (id)centralIconForIcon:(id)icon;

- (NSString *)layoutPathForIconID:(NSString *)iconID;
- (NSString *)layoutPathForIcon:(SBIcon *)icon;

- (BOOL)iconHasStack:(SBIcon *)icon;
- (BOOL)iconIsInStack:(SBIcon *)icon;

- (BOOL)removeLayoutForIcon:(SBIcon *)icon;
- (BOOL)removeLayoutForIconID:(NSString *)iconID;

- (id)registerCallbackForPrefsChange:(STKPreferencesCallbackBlock)callbackBlock;
- (void)unregisterCallbackWithObserver:(id)observer;

- (NSDictionary *)cachedLayoutDictForIcon:(SBIcon *)centralIcon;
- (void)refreshCachedLayoutDictForIcon:(SBIcon *)centralIcon;

@end