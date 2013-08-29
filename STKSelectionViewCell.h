#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, STKSelectionViewCellLabelPosition) {
	STKSelectionViewCellLabelPositionRight = 1,
	STKSelectionViewCellLabelPositionLeft
};

@class SBIcon, SBIconView;

@interface STKSelectionViewCell : UITableViewCell

@property (nonatomic, retain) SBIcon *icon;
@property (nonatomic, readonly) SBIconView *iconView;
@property (nonatomic, assign) NSInteger hitTestOverrideSubviewTag;

@end
