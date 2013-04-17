#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SBIconView.h>


@class SBIcon;
@interface STKStackManager : NSObject <SBIconViewDelegate>

typedef void(^STKInteractionHandler)(SBIconView *tappedIconView);

@property(nonatomic, readonly) BOOL hasSetup;
@property(nonatomic, readonly) BOOL isExpanded;

// The interaction handler is called when an icon is tapped.
- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons interactionHandler:(STKInteractionHandler)handler;

// Setup view must be called ***only** once. This method adds creates and add iconviews underneath the central icon
- (void)setupView;

- (void)touchesDraggedForDistance:(CGFloat)distance;

// Reset icons' layouts when the central icon's position is changed by the user
- (void)recalculateLayoutsWithStackIcons:(NSArray *)icons;

// Call this method when the swipe ends, so as to decide whether to keep the stack open, or to close it.
- (void)touchesEnded;

// Close the stack irrespective of what's happening. -touchesEnded might call this.
- (void)closeStack;

@end
