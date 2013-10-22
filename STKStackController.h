#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>

#import "STKStackDelegate-Protocol.h"
#import "STKStack.h"

@class STKStack;
@interface STKStackController : NSObject <STKStackDelegate, UIGestureRecognizerDelegate>

+ (instancetype)sharedInstance;

@property (nonatomic, retain) STKStack *activeStack;

- (void)createOrRemoveStackForIconView:(SBIconView *)iconView;
- (void)createStackForIconView:(SBIconView *)iconView;
- (void)removeStackFromIconView:(SBIconView *)iconView;

- (void)addRecognizerToIconView:(SBIconView *)iconView;
- (void)removeRecognizerFromIconView:(SBIconView *)iconView;

- (void)addGrabbersToIconView:(SBIconView *)iconView;
- (void)removeGrabbersFromIconView:(SBIconView *)iconView;
- (NSArray *)grabberViewsForIconView:(SBIconView *)iconView;

- (STKStack *)stackForIconView:(SBIconView *)iconView;

- (void)closeActiveStack;

@end
