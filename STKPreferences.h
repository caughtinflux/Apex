#import "STKConstants.h"

@class STKGroup;
@interface STKPreferences : NSObject <STKGroupObserver>

+ (instancetype)sharedPreferences;

@property (nonatomic, readonly) STKActivationMode activationMode;
@property (nonatomic, readonly) BOOL shouldLockLayouts;
@property (nonatomic, readonly) BOOL shouldShowhowPreview;

- (void)addOrUpdateGroup:(STKGroup *)group;
- (void)removeGroup:(STKGroup *)group;

- (STKGroup *)groupForIcon:(SBIcon *)icon;

@end
