#import <UIKit/UIKit.h>

@class SBIconView, STKIconLayout;

@interface STKSelectionListView : UIView

/**
*	Returns: STKSelectionListView instance.
*
*	Param `iconView`: The icon view around which the selection UI is to be shown
*	Param `iconViewsLayout`: The layout containing SBIconView instances of all the icons in the stack
*	Param `centralIconView`: The central icon view for the stack
*	Param `displacedIconsLayout`: Layout containing homescreen icons that are displaced
*/
- (instancetype)initWithIconView:(SBIconView *)iconView inLayout:(STKIconLayout *)iconViewLayout centralIconView:(SBIconView *)centralIconView displacedIcons:(STKIconLayout *)displacedIconsLayout;

@end
