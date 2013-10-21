#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>

#import "STKStackDelegate-Protocol.h"

@class STKStack;
@interface STKStackController : NSObject <STKStackDelegate>

@property (nonatomic, readonly) STKStack *activeStack;

+ (instancetype)sharedInstance;

- (void)createStackForIconView:(SBIconView *)iconView;
- (void)removeStackFromIconView:(SBIconView *)iconView;

- (void)addRecognizerToIconView:(SBIconView *)iconView;
- (void)removeRecognizerFromIconView:(SBIconView *)iconView;

- (void)addGrabbersToIconView:(SBIconView *)iconView;
- (void)removeGrabbersFromIconView:(SBIconView *)iconView;
- (NSArray *)grabberViewsForIconView:(SBIconView *)iconView;

- (STKStack *)stackForView:(SBIconView *)iconView;

@end
