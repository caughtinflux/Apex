#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "STKSelectionViewCell.h"

@class SBIcon, SBIconView;
@interface STKSelectionViewDataSource : NSObject <UITableViewDataSource>

@property (nonatomic, retain) SBIconView *centralView;
@property (nonatomic, assign) STKSelectionCellPosition cellPosition;

- (void)prepareData;
- (SBIcon *)iconAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)indexPathForIcon:(SBIcon *)icon;

@end

