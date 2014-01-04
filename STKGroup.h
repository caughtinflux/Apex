#import <Foundation/Foundation.h>
#import "STKGroupLayout.h"
#import "STKConstants.h"

@protocol STKGroupObserver;

@class SBIcon, STKGroupLayout;
@interface STKGroup : NSObject

- (instancetype)initWithCentralIcon:(SBIcon *)icon layout:(STKGroupLayout *)layout;

@property (nonatomic, retain) SBIcon *centralIcon;
@property (nonatomic, readonly) STKGroupLayout *layout;
@property (nonatomic, readonly) NSDictionary *dictionaryRepresentation;

- (void)addObserver:(id<STKGroupObserver>)observer;
- (void)removeObserver:(id<STKGroupObserver>)observer;

@end

@protocol STKGroupObserver <NSObject>
@required
- (void)group:(STKGroup *)group didAddIcons:(NSArray *)addedIcons removedIcons:(NSArray *)removingIcons;
@end
