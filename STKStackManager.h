#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SBIconView.h>


@class SBIcon;
@interface STKStackManager : NSObject <SBIconViewDelegate>

typedef void(^STKInteractionHandler)(SBIconView *tappedIconView);

@property(nonatomic, readonly) BOOL hasSetup;

- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons interactionHandler:(STKInteractionHandler)handler;
- (void)setupView;
- (void)touchesDraggedForDistance:(CGFloat)distance;

// Call this method when the swipe ends, so as to decide whether to keep the stack open, or to close it.
- (void)touchesEnded;
- (void)closeStack;

@end
