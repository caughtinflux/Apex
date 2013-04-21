#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SBIconView.h>


@class SBIcon;
@interface STKStackManager : NSObject <SBIconViewDelegate>

typedef void(^STKInteractionHandler)(SBIconView *tappedIconView);

@property(nonatomic, readonly) BOOL hasSetup;
@property(nonatomic, readonly) BOOL isExpanded;
@property(nonatomic, readonly) CGFloat currentIconDistance; // Distance of all the icons from the center.
@property(nonatomic, copy) STKInteractionHandler interactionHandler;

// The interaction handler is called when an icon is tapped.
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons;

- (void)setupViewIfNecessary;
- (void)setupView;

- (void)touchesDraggedForDistance:(CGFloat)distance;

// Call this method when the swipe ends, so as to decide whether to keep the stack open, or to close it.
- (void)touchesEnded;

// Close the stack irrespective of what's happening. -touchesEnded might call this.
- (void)closeStackWithCompletionHandler:(void(^)(void))completionHandler;

// This method sets the central icon to `icon` until _after_ `handler` is called
- (void)closeStackSettingCentralIcon:(SBIcon *)icon completion:(void(^)(void))handler;

- (void)closeStack; // convenience method

@end
