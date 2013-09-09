#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SBIconViewDelegate-Protocol.h>
#import "STKSelectionView.h"

#ifdef __cplusplus 
extern "C" {
#endif
    extern NSString * const STKStackManagerCentralIconKey;
    extern NSString * const STKStackManagerStackIconsKey;
    extern NSString * const STKStackManagerCustomLayoutKey;

    extern NSString * const STKRecalculateLayoutsNotification;
#ifdef __cplusplus
}
#endif

#define kEnablingThreshold 33

typedef void(^STKInteractionHandler)(id manager, SBIconView *tappedIconView, BOOL didChangeState, SBIcon *addedIcon);

@class SBIcon, STKIconLayout;

@interface STKStackManager : NSObject <SBIconViewDelegate, UIGestureRecognizerDelegate, STKSelectionViewDelegate>

+ (BOOL)isValidLayoutAtPath:(NSString *)path;

/**
*   Properties to derive information from
*/
@property (nonatomic, readonly) BOOL hasSetup;
@property (nonatomic, readonly) BOOL isExpanded;
@property (nonatomic, readonly) BOOL isEmpty;
@property (nonatomic, readonly) BOOL layoutDiffersFromFile;
@property (nonatomic, readonly) CGFloat currentIconDistance; // Distance of all the icons from the center.
@property (nonatomic, readonly) SBIcon *centralIcon;
@property (nonatomic, readonly) STKIconLayout *appearingIconsLayout;
@property (nonatomic, readonly) STKIconLayout *disappearingIconsLayout;

@property (nonatomic, copy) STKInteractionHandler interactionHandler; // the tappedIconView is only passed if there indeed was a tapped icon view. This may be called even if a swipe/tap is detected on the content view, and the stack closes automagically.

@property (nonatomic, assign) BOOL isEditing;
@property (nonatomic, assign) BOOL closesOnHomescreenEdit; 
@property (nonatomic, assign) BOOL showsPreview;

/**
*   @return An instance of STKStackManager, nil if `file` is corrupt or could not be read
*   @param file Path to an archived dictionary that looks like this:   @{STKStackManagerCentralIconKey: <central icon identifier>,
*                                                                        STKStackManagerStackIconsKey: <array of stack icon identifiers>,
                                                                         STKStackManagerCustomLayoutKey: <dict containing a custom layout>}
*/
- (instancetype)initWithContentsOfFile:(NSString *)file;

/**
*   @return An instance of STKStackManager
*   @param centralIcon The icon on the home screen that will be at the centre of the stack
*   @param icons Sub-apps in the stack. Pass nil for this argument to display empty placeholders
*/
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons;

/**
*	@return An instance of STKStackManager
*	@param centralIcon The icon on the home screen that will be at the centre of the stack
*	@param customLayout A dictionary for STKIconLayout to init with
*/
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon withCustomLayout:(NSDictionary *)customLayout;

/**
*   Persist the layout to path
*   @param path The full path to which the layout is to be persisted
*   @warning *Warning*: path must be writable
*   @see file
*/
- (void)saveLayoutToFile:(NSString *)path;

/**
*   Call this method when the location of the icon changes
*   You can also send STKRecaluculateLayoutsNotification through +[NSNotificationCenter defaultCenter]
*/
- (void)recalculateLayouts;

- (void)removeIconFromAppearingIcons:(SBIcon *)icon;

/**
*   Sets up the "app-peeking" preview for each app
*   @warning *Important*: Calls setupView if necessary
*   @see setupView
*/
- (void)setupPreview;

/**
*    Set Up Stack Icons' Views
*/
- (void)setupViewIfNecessary;
- (void)setupView;
- (void)cleanupView;

/**
*   Call this method to prepare the manager
*/
- (void)touchesBegan;

- (void)touchesDraggedForDistance:(CGFloat)distance;

/**
*   Call this method when the swipe ends, so as to decide whether to keep the stack open, or to close it.
*   If the stack opens up, the receiver automatically sets up swipe and tap recognisers on the icon content view, which, when fired, will call the interactionHandler with a nil argument.
*/
- (void)touchesEnded;

/**
*   Close the stack irrespective of what's happening. -touchesEnded might call this.
*   @param completionHandler Block that will be called once stack closing animations finish
*/
- (void)closeStackWithCompletionHandler:(void(^)(void))completionHandler;
- (void)closeForSwitcherWithCompletionHandler:(void(^)(void))completionHandler;

/**
*   Convenience methods
*/
- (void)openStack;
- (void)closeStack;

/**
*	Self-Explanatory
*	@return YES if the press was intercepted.
*/
- (BOOL)handleHomeButtonPress;

- (void)setStackIconAlpha:(CGFloat)alpha;

/**
*   HAXX: This method should be called as a proxy for -[UIView hitTest:withEvent:] inside SBIconView, so we can process if any stack icons should be receiving touches.
*   It's necessary, because the icons are added as a subview of the central iconView.
*   Parameters same as -[UIView hitTest:withEvent:]
*/
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;

@end
