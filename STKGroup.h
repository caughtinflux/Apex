#import <Foundation/Foundation.h>
#import "STKGroupLayout.h"

@protocol STKGroupObserver;

typedef struct STKGroupSlot {
	STKLayoutPosition position;
	NSUInteger index;
} STKGroupSlot;

@class SBIcon, STKGroupLayout;
@interface STKGroup : NSObject

- (instancetype)initWithCentralIcon:(SBIcon *)icon layout:(STKGroupLayout *)layout;

@property (nonatomic, retain) SBIcon *centralIcon;
@property (nonatomic, readonly) STKGroupLayout *layout;
@property (nonatomic, readonly) NSDictionary *dictionaryRepresentation;

// Call this method after modifying the layout
- (void)processLayout;

- (void)insertIcon:(SBIcon *)icon inSlot:(STKGroupSlot)slot;
- (void)removeIcon:(SBIcon *)icon fromSlot:(STKGroupSlot)slot;

- (void)addObserver:(id<STKGroupObserver>)observer;
- (void)removeObserver:(id<STKGroupObserver>)observer;

@end

@protocol STKGroupObserver <NSObject>
@required
- (void)group:(STKGroup *)group didUpdateLayoutByAddingIcons:(NSArray *)addedIcons removingIcons:(NSArray *)removingIcons;
@end
