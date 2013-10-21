#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "STKIconLayout.h"

@class STKStack, SBIcon, SBIconView;
@protocol STKStackDelegate <NSObject>

@optional
- (void)stack:(STKStack *)stack didReceiveTapOnIconView:(SBIconView *)iconView;
- (void)stackDidCloseAfterPanEnded:(STKStack *)stack;
- (void)stackClosedByGesture:(STKStack *)stack;

@required
/**
*	Called when the layout of the stack changes
*/
- (void)stackDidUpdateState:(STKStack *)stack;

/**
*	@param stack The stack to which `icon is added
*	@param icon This will be nil if an icon was removed from `position` at `idx`
*/
- (void)stack:(STKStack *)stack didAddIcon:(SBIcon *)icon removingIcon:(SBIcon *)icon atPosition:(STKLayoutPosition)position index:(NSUInteger)idx;

@end
