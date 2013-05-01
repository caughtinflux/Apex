#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SBIconViewDelegate-Protocol.h>

typedef void(^STKInteractionHandler)(SBIconView *tappedIconView);

@class SBIcon;

@interface STKStackManager : NSObject <SBIconViewDelegate, UIGestureRecognizerDelegate>

+ (BOOL)anyStackOpen;
+ (BOOL)anyStackInMotion;

@property(nonatomic, readonly) BOOL hasSetup;
@property(nonatomic, readonly) BOOL isExpanded;
@property(nonatomic, readonly) CGFloat currentIconDistance; // Distance of all the icons from the center.

@property(nonatomic, copy) STKInteractionHandler interactionHandler; // the tappedIconView is only passed if there indeed was a tapped icon view. This may be called even if a swipe/tap is detected on the content view, and the stack closes automagically.

- (instancetype)initWithContentsOfFile:(NSString *)file;

// The interaction handler is called when an icon is tapped.
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons;

// Persistence
- (void)writeToFile:(NSString *)path;

// Sets up stack iconViews
- (void)setupViewIfNecessary;
- (void)setupView;

- (void)touchesDraggedForDistance:(CGFloat)distance;

/*
	Call this method when the swipe ends, so as to decide whether to keep the stack open, or to close it.
	If the stack opens up, the receiver automatically sets up swipe and tap recognisers on the icon content view, which, when fired, will call the interactionHandler with a nil argument.
*/
- (void)touchesEnded;

// Close the stack irrespective of what's happening. -touchesEnded might call this.
- (void)closeStackWithCompletionHandler:(void(^)(void))completionHandler;

// This method sets the central icon to `icon` until _after_ `handler` is called
- (void)closeStackSettingCentralIcon:(SBIcon *)icon completion:(void(^)(void))handler;

// convenience methods
- (void)openStack;
- (void)closeStack;
- (void)closeStackAfterDelay:(NSTimeInterval)delay completion:(void(^)(void))completionBlock;

- (void)modifyIconModel;
- (void)restoreIconModel;

@end
