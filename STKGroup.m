#import "STKGroup.h"
#import "STKGroupLayout.h"
#import "STKGroupLayoutHandler.h"
#import "STKConstants.h"

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

NSString * const STKGroupCentralIconKey = @"STKGroupCentralIcon";
NSString * const STKGroupLayoutKey = @"STKGroupLayout";

@implementation STKGroup
{
	STKGroupLayout *_layout;
	NSHashTable *_observers;
}

- (instancetype)initWithCentralIcon:(SBIcon *)icon layout:(STKGroupLayout *)layout
{
	if ((self = [super init])) {
		_centralIcon = [icon retain];
		_layout = [layout retain];
		_observers = [[NSHashTable alloc] initWithOptions:NSHashTableWeakMemory capacity:0];
	}
	return self;
}

- (STKGroupLayout *)layout
{
	return _layout;
}

- (NSDictionary *)dictionaryRepresentation
{
	return @{
		STKGroupCentralIconKey: [_centralIcon leafIdentifier] ?: @"",
		STKGroupLayoutKey: [_layout identifierDictionary] ?: @{}
	};
}

// Call this method after modifying the layout
- (void)processLayout
{

}

- (void)insertIcon:(SBIcon *)icon inSlot:(STKGroupSlot)slot
{

}

- (void)removeIcon:(SBIcon *)icon fromIconsInSlot:(STKGroupSlot)slot
{
	[_layout removeIcon:icon fromIconsAtPosition:slot.position];
}

- (void)addObserver:(id<STKGroupObserver>)observer
{
	[_observers addObject:observer];
}

- (void)removeObserver:(id<STKGroupObserver>)observer
{
	[_observers removeObject:observer];		
}

- (SBIconView *)_iconViewForIcon:(SBIcon *)icon
{
	return [[CLASS(SBIconViewMap) homescreenMap] mappedIconViewForIcon:icon];
}

@end
