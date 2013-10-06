#import <UIKit/UIKit.h>
#import "STKIconLayoutHandler.h"

@class SBIconView, STKIconLayout, STKSelectionViewDataSource;
@protocol STKSelectionViewDelegate;
@interface STKSelectionView : UIView <UIScrollViewDelegate, UITableViewDelegate>
{
@private
    SBIconView *_selectedView;
    SBIconView *_centralView;
    
    STKIconLayout *_iconViewsLayout;
    STKIconLayout *_displacedIconsLayout;

    id<STKSelectionViewDelegate> _delegate;
}

/**
*   @param iconView The icon view around which the selection UI is to be shown
*   @param iconViewLayout The layout containing SBIconView instances of all the icons in the stack
*	@param position The bitmask containing position of the central icon view
*   @param centralIconView The central icon view for the stack
*   @param displacedIconsLayout Layout containing homescreen icons that are displaced
*	
*	@return STKSelectionListView instance, with an automatically calculated frame
*/
- (instancetype)initWithIconView:(SBIconView *)iconView
                        inLayout:(STKIconLayout *)iconViewLayout
                        position:(STKPositionMask)position
                 centralIconView:(SBIconView *)centralIconView
                  displacedIcons:(STKIconLayout *)displacedIconsLayout;

/**
*   All these properties are simply the arguments passed into the designated intializer
*/
@property (nonatomic, readonly) SBIconView *iconView; // iconView=_selectedView
@property (nonatomic, readonly) SBIconView *centralIconView;
@property (nonatomic, readonly) STKIconLayout *iconViewsLayout;
@property (nonatomic, readonly) STKIconLayout *displacedIconsLayout;
@property (nonatomic, readonly) UITableView *listTableView;

@property (nonatomic, readonly) STKSelectionViewDataSource *dataSource;

/*
*	The currently selected icon in the list.
*/
@property (nonatomic, readonly) SBIcon *highlightedIcon;

/**
*   Set this property to be notified about events in the selection view
*/
@property (nonatomic, assign) id<STKSelectionViewDelegate> delegate;

- (void)scrollToDefaultAnimated:(BOOL)animated;
- (void)moveToIconView:(SBIconView *)iconView animated:(BOOL)animated completion:(void(^)(void))completionBlock;

- (void)prepareForDisplay;
- (void)prepareForRemoval;

@end


@protocol STKSelectionViewDelegate <NSObject>
@optional
- (void)closeButtonTappedOnSelectionView:(STKSelectionView *)selectionView;
@end

