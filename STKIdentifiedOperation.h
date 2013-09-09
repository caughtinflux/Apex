#import <Foundation/Foundation.h>

@interface STKIdentifiedOperation : NSOperation
{
@private
	void (^_executionBlock)(void);
	NSString *_identifier;
	dispatch_queue_t _queue;
}

+ (instancetype)operationWithBlock:(void(^)(void))block identifier:(NSString *)identifier queue:(dispatch_queue_t)queue;
- (instancetype)initWithBlock:(void(^)(void))block identifier:(NSString *)identifier queue:(dispatch_queue_t)queue;

@property (nonatomic, readonly) NSString *identifier;

@end
