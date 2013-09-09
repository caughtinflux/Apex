#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, STKSelectionCellPosition) {
	STKSelectionCellPositionRight = 1,
	STKSelectionCellPositionLeft
};

@class SBIcon, SBIconView;

@interface STKSelectionViewCell : UITableViewCell

@property (nonatomic, retain) SBIcon *icon;
@property (nonatomic, readonly) SBIconView *iconView;
@property (nonatomic, assign) NSInteger hitTestOverrideSubviewTag;

@property (nonatomic, assign) STKSelectionCellPosition position;

@end
