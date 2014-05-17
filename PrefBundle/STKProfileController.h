#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "Globals.h"
#import "PrefsHelper.h"
#import "STKTableViewCell.h"

@interface STKProfileController : PSViewController <UITableViewDelegate, UITableViewDataSource> {
@private
    UITableView *_tableView;
}

@end
