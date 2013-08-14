#import <UIKit/UIKit.h>
#import "STKIconLayoutHandler.h"


@class SBIconView, STKIconLayout;
@protocol STKSelectionViewDelegate;

@interface STKSelectionView : UIView <UITableViewDelegate, UITableViewDataSource>
{
@private
    SBIconView *_selectedView;
    SBIconView *_centralView;
    
    STKIconLayout *_iconViewsLayout;
    STKIconLayout *_displacedIconsLayout;

    id<STKSelectionViewDelegate> _delegate;
}

/**
*   Returns: STKSelectionListView instance.
*
*   Param `iconView`: The icon view around which the selection UI is to be shown
*   Param `iconViewsLayout`: The layout containing SBIconView instances of all the icons in the stack
*   Param `centralIconView`: The central icon view for the stack
*   Param `displacedIconsLayout`: Layout containing homescreen icons that are displaced
*/
- (instancetype)initWithIconView:(SBIconView *)iconView
                        inLayout:(STKIconLayout *)iconViewLayout
                        position:(STKPositionMask)position
                 centralIconView:(SBIconView *)centralIconView
                  displacedIcons:(STKIconLayout *)displacedIconsLayout;

/**
*   All these properties are simply the arguments passed into the designated intializer
*/
@property (nonatomic, readonly) SBIconView *iconView;
@property (nonatomic, readonly) SBIconView *centralIconView;
@property (nonatomic, readonly) STKIconLayout *iconViewsLayout;
@property (nonatomic, readonly) STKIconLayout *displacedIconsLayout;
@property (nonatomic, readonly) UITableView *listTableView;

/**
*   Set this property to be notified about events in the selection view
*/
@property (nonatomic, assign) id<STKSelectionViewDelegate> delegate;

@end


@protocol STKSelectionViewDelegate <NSObject>
@optional
- (void)iconView:(SBIconView *)iconView tappedInSelectionView:(STKSelectionView *)selectionView;
@end

