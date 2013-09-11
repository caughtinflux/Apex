#import <UIKit/UIKit.h>
#import "PrefsHelper.h"

__attribute__((visibility("hidden")))
@interface STKTableViewCellProfile : UITableViewCell {
@private
    UIImageView *profileView;
    UIImageView *birdView;
    
    UILabel *nameLabel;
    UILabel *handleLabel;
    UILabel *infoLabel;
}

- (void)loadImage:(NSString *)imageName nameText:(NSString *)nameText handleText:(NSString *)handleText infoText:(NSString *)infoText;

@end
