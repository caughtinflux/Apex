#import <Foundation/Foundation.h>

typedef void(^STKPreferencesCallback)(void);

#ifdef __cplusplus
extern "C" {
#endif
	extern NSString * const STKPreferencesChangedNotification;
#ifdef __cplusplus
}
#endif

@class STKIconLayout, SBIcon;
@interface STKPreferences : NSObject

+ (NSString *)layoutsDirectory;
+ (NSString *)layoutPathForIconID:(NSString *)iconID;
+ (NSString *)layoutPathForIcon:(SBIcon *)icon;

+ (BOOL)isValidLayoutAtPath:(NSString *)path;
+ (BOOL)isValidLayout:(NSDictionary *)dict;

+ (void)saveLayout:(STKIconLayout *)layout forIcon:(SBIcon *)centralIcon;

+ (instancetype)sharedPreferences;
- (void)reloadPreferences;

@property (nonatomic, readonly) NSArray *identifiersForIconsInStacks;
@property (nonatomic, readonly) BOOL previewEnabled;
@property (nonatomic, readonly) BOOL shouldHideGrabbers;
@property (nonatomic, assign) BOOL welcomeAlertShown;
@property (nonatomic, readonly) BOOL shouldCloseOnLaunch;
@property (nonatomic, readonly) BOOL shouldShowSectionIndexTitles;

- (NSSet *)identifiersForIconsWithStack;
- (NSArray *)stackIconsForIcon:(SBIcon *)icon;

// Pass in a NSString for `icon`, you get an NSString in return
// If `icon` is a SBIcon instance, you get a SBIcon in return!
- (id)centralIconForIcon:(id)icon;

- (BOOL)iconHasStack:(SBIcon *)icon;
- (BOOL)iconIsInStack:(SBIcon *)icon;

- (BOOL)removeLayoutForIcon:(SBIcon *)icon;
- (BOOL)removeLayoutForIconID:(NSString *)iconID;

- (void)registerCallbackForPrefsChange:(STKPreferencesCallback)callbackBlock;

- (NSDictionary *)cachedLayoutDictForIcon:(SBIcon *)centralIcon;
- (void)removeCachedLayoutForIcon:(SBIcon *)centralIcon;

@end
