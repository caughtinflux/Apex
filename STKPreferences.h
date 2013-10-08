#import <Foundation/Foundation.h>

typedef void(^STKPreferencesCallback)(void);

@class SBIcon;
@interface STKPreferences : NSObject

+ (NSString *)layoutsDirectory;

+ (instancetype)sharedPreferences;

- (void)reloadPreferences;

@property (nonatomic, readonly) NSArray *identifiersForIconsInStacks;
@property (nonatomic, assign) BOOL previewEnabled;
@property (nonatomic, assign) BOOL welcomeAlertShown;

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

- (void)registerCallbackForPrefsChange:(STKPreferencesCallback)callbackBlock;

- (NSDictionary *)cachedLayoutDictForIcon:(SBIcon *)centralIcon;
- (void)removeCachedLayoutForIcon:(SBIcon *)centralIcon;

@end
