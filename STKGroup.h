#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>

#ifdef __cplusplus
extern "C" {
#endif
    extern NSString * const STKGroupCentralIconKey;
    extern NSString * const STKGroupLayoutKey;
    extern NSString * const STKGroupCoordinateKey;
#ifdef __cplusplus
}
#endif


@class STKGroupView, STKGroupLayout;
@protocol STKGroupObserver;
@interface STKGroup : NSObject

- (instancetype)initWithCentralIcon:(SBIcon *)icon layout:(STKGroupLayout *)layout;
- (instancetype)initWithDictionary:(NSDictionary *)repr;

@property (nonatomic, retain) SBIcon *centralIcon;
@property (nonatomic, readonly) STKGroupLayout *layout;
@property (nonatomic, readonly) NSDictionary *dictionaryRepresentation;
@property (nonatomic, assign) SBIconCoordinate lastKnownCoordinate;
@property (nonatomic, assign, getter=isEmpty) BOOL empty;

- (void)addObserver:(id<STKGroupObserver>)observer;
- (void)removeObserver:(id<STKGroupObserver>)observer;

@end

@protocol STKGroupObserver <NSObject>
@required
- (void)group:(STKGroup *)group didAddIcons:(NSArray *)addedIcons removedIcons:(NSArray *)removingIcons;
@end
