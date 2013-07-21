#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SBIconViewDelegate-Protocol.h>

typedef void(^STKInteractionHandler)(SBIconView *tappedIconView);

#ifdef __cplusplus 
extern "C" {
#endif
    extern NSString * const STKStackManagerCentralIconKey;
    extern NSString * const STKStackManagerStackIconsKey;
    extern NSString * const STKRecaluculateLayoutsNotification;
#ifdef __cplusplus
}
#endif

#define kEnablingThreshold 33

@class SBIcon, STKIconLayout;

@interface STKStackManager : NSObject <SBIconViewDelegate, UIGestureRecognizerDelegate>

+ (BOOL)anyStackOpen;
+ (BOOL)anyStackInMotion;
+ (NSString *)layoutsPath;

// Properties to derive information from
@property (nonatomic, readonly) BOOL hasSetup;
@property (nonatomic, readonly) BOOL isExpanded;
@property (nonatomic, readonly) BOOL isEmpty;
@property (nonatomic, readonly) CGFloat currentIconDistance; // Distance of all the icons from the center.
@property (nonatomic, readonly) SBIcon *centralIcon;
@property (nonatomic, readonly) STKIconLayout *appearingIconsLayout;
@property (nonatomic, readonly) STKIconLayout *disappearingIconsLayout;

@property (nonatomic, copy) STKInteractionHandler interactionHandler; // the tappedIconView is only passed if there indeed was a tapped icon view. This may be called even if a swipe/tap is detected on the content view, and the stack closes automagically.

@property (nonatomic, assign) BOOL isEditing;
@property (nonatomic, assign) BOOL closesOnHomescreenEdit; 

- (instancetype)initWithContentsOfFile:(NSString *)file;

// Pass in nil to stack icons for creating a manager with all placeholders.
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons;

// Persistence
- (void)saveLayoutToFile:(NSString *)path;

// Call this method when the location of the icon changes
// You can also send STKRecaluculateLayoutsNotification
- (void)recalculateLayouts;

- (void)setupPreview;

// Set Up Stack Icons' Views
- (void)setupViewIfNecessary;
- (void)setupView;
- (void)cleanupView;

- (void)touchesDraggedForDistance:(CGFloat)distance;

/*
    Call this method when the swipe ends, so as to decide whether to keep the stack open, or to close it.
    If the stack opens up, the receiver automatically sets up swipe and tap recognisers on the icon content view, which, when fired, will call the interactionHandler with a nil argument.
*/
- (void)touchesEnded;

// Close the stack irrespective of what's happening. -touchesEnded might call this.
- (void)closeStackWithCompletionHandler:(void(^)(void))completionHandler;
- (void)closeForSwitcher;

// convenience methods
- (void)openStack;
- (void)closeStack;

- (void)setStackIconAlpha:(CGFloat)alpha;

// HAXX: This method should be called as a proxy for -[UIView hitTest:withEvent:] inside SBIconView, so we can process if any stack icons should be receiving touches.
// It's necessary, because the icons are added as a subview of the central iconView.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;

@end
