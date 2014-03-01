#import "STKConstants.h"

@class STKGroup;
@interface STKPreferences : NSObject <STKGroupObserver>

+ (instancetype)sharedPreferences;
- (void)reloadPreferences;

@property (nonatomic, readonly) STKActivationMode activationMode;
@property (nonatomic, readonly) BOOL shouldLockLayouts;
@property (nonatomic, readonly) BOOL shouldShowPreviews;
@property (nonatomic, readonly) NSArray *identifiersForSubappIcons;

- (void)addOrUpdateGroup:(STKGroup *)group;
- (void)removeGroup:(STKGroup *)group;

- (STKGroup *)groupForCentralIcon:(SBIcon *)icon;
- (STKGroup *)groupForSubappIcon:(SBIcon *)icon;

@end
