#import <Foundation/Foundation.h>

@interface NSOperationQueue (STKMainQueueDispatch)
- (void)stk_addOperationToRunOnMainThreadWithBlock:(void(^)(void))block;
@end
