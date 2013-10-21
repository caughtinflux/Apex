#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>


@class STKStack;
@interface STKStackController : NSObject

@property (nonatomic, readonly) STKStack *activeStack;

+ (instancetype)sharedInstance;
- (void)setupIconView:(SBIconView *)iconView;

@end
