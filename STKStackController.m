#import "STKStackController.h"
#import "STKConstants.h"

@interface STKStackController ()
{
	STKStack *_activeStack;
}

@end


@implementation STKStackController

+ (instancetype)sharedInstance
{
	static id _sharedInstance;

	dispatch_once_t predicate;
	dispatch_once(&predicate, ^{
		_sharedInstance = [[self alloc] init];
	});

	return _sharedInstance;
}

@end
