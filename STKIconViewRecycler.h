#import <Foundation/Foundation.h>
#import "STKConstants.h"

@protocol STKIconViewRecyclerDelegate;
@class SBIcon, SBIconView;
@interface STKIconViewRecycler : NSObject <STKIconViewSource>
- (id)iconViewForIcon:(SBIcon *)icon;
- (void)recycleIconView:(SBIconView *)iconView;
@end
