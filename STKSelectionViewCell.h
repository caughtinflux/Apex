#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, STKSelectionViewCellLabelPosition) {
	STKSelectionViewCellLabelPositionRight = 1,
	STKSelectionViewCellLabelPositionLeft
};

@class SBIcon;

@interface STKSelectionViewCell : UITableViewCell

@property (nonatomic, retain) SBIcon *icon;

@end
