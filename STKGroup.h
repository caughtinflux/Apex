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

typedef NS_ENUM(NSUInteger, STKGroupState) {
	STKGroupStateInvalid = -1,
	STKGroupStateNormal,
	STKGroupStateEmpty,
	STKGroupStateEditing,
	STKGroupStateQuasiEmpty
};

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
@property (nonatomic, readonly) STKGroupState state;

- (void)addObserver:(id<STKGroupObserver>)observer;
- (void)removeObserver:(id<STKGroupObserver>)observer;

- (void)replaceIconAtSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon;
- (void)removeIconAtSlot:(STKGroupSlot)slot;

@end

@protocol STKGroupObserver <NSObject>
@required
- (void)group:(STKGroup *)group didAddIcon:(NSArray *)addedIcon removedIcon:(NSArray *)removingIcon;
@end
