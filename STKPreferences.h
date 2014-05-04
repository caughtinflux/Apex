#import "STKConstants.h"

@class STKGroup;
@interface STKPreferences : NSObject <STKGroupObserver>

+ (instancetype)sharedPreferences;
- (void)reloadPreferences;

@property (nonatomic, readonly) STKActivationMode activationMode;
@property (nonatomic, readonly) BOOL shouldLockLayouts;
@property (nonatomic, readonly) BOOL shouldShowPreviews;
@property (nonatomic, readonly) BOOL shouldShowSummedBadges;
@property (nonatomic, readonly) BOOL shouldCloseOnLaunch;
@property (nonatomic, readonly) BOOL shouldHideGrabbers;
@property (nonatomic, readonly) BOOL shouldDisableSearchGesture;
@property (nonatomic, assign) BOOL welcomeAlertShown;

@property (nonatomic, readonly) NSArray *identifiersForSubappIcons;

- (void)addOrUpdateGroup:(STKGroup *)group;
- (void)removeGroup:(STKGroup *)group;

- (STKGroup *)groupForCentralIcon:(SBIcon *)icon;
- (STKGroup *)groupForSubappIcon:(SBIcon *)icon;

@end
