#import "STKIdentifiedOperation.h"

@implementation STKIdentifiedOperation

+ (instancetype)operationWithBlock:(void(^)(void))block identifier:(NSString *)identifier queue:(dispatch_queue_t)queue
{
	return [[[self alloc] initWithBlock:block identifier:identifier queue:queue] autorelease];
}

- (instancetype)initWithBlock:(void(^)(void))block identifier:(NSString *)identifier queue:(dispatch_queue_t)queue
{
	NSAssert((block != nil), (@"-[STKIdentifiedOperation initWithBlock:identifier:] cannot have a nil argument for the block!"));
	if ((self = [super init])) {
		_executionBlock = [block copy];
		_identifier = [identifier copy];
		_queue = queue;
		dispatch_retain(_queue);
	}
	return self;
}

- (void)dealloc
{
	[_executionBlock release];
	[_identifier release];
	dispatch_release(_queue);

	[super dealloc];
}

- (void)main
{
	if (_executionBlock) {
		dispatch_async(dispatch_get_main_queue(), ^{
			_executionBlock();
		});
	}
}

@end
