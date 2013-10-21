#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SBIconViewDelegate-Protocol.h>
#import "STKSelectionView.h"
#import "STKStackDelegate-Protocol.h"

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

@interface STKStack : NSObject <SBIconViewDelegate, UIGestureRecognizerDelegate, STKSelectionViewDelegate>
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
@property (nonatomic, readonly) STKIconLayout *iconViewsLayout;
@property (nonatomic, readonly) STKIconLayout *disappearingIconsLayout;
@property (nonatomic, readonly) CGFloat distanceRatio;
@property (nonatomic, readonly) BOOL isSelecting;

@property (nonatomic, assign) BOOL isEditing;
@property (nonatomic, assign) BOOL showsPreview;

@property (nonatomic, retain) UIView *topGrabberView;
@property (nonatomic, retain) UIView *bottomGrabberView;

@property (nonatomic, assign) id<STKStackDelegate> delegate;

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
- (void)closeWithCompletionHandler:(void(^)(void))completionHandler;
- (void)closeForSwitcherWithCompletionHandler:(void(^)(void))completionHandler;

/**
*   Convenience methods
*/
- (void)open;
- (void)close;

/**
*	Self-Explanatory
*	@return YES if the press was intercepted.
*/
- (BOOL)handleHomeButtonPress;

- (void)setIconAlpha:(CGFloat)alpha;

/**
*   HAXX: This method should be called as a proxy for -[UIView hitTest:withEvent:] inside SBIconView, so we can process if any stack icons should be receiving touches.
*   It's necessary, because the icons are added as a subview of the central iconView.
*   Parameters same as -[UIView hitTest:withEvent:]
*/
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;

@end
