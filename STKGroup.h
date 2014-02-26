#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>
#import "STKTypes.h"

#ifdef __cplusplus
extern "C" {
#endif
    extern NSString * const STKGroupCentralIconKey;
    extern NSString * const STKGroupLayoutKey;
    extern NSString * const STKGroupCoordinateKey;
#ifdef __cplusplus
}
#endif

typedef NS_ENUM(NSInteger, STKGroupState) {
    STKGroupStateInvalid = -1,
    STKGroupStateNormal,
    STKGroupStateEmpty,
    STKGroupStateDirty
};

@class STKGroupView, STKGroupLayout;
@protocol STKGroupObserver;
@interface STKGroup : NSObject

- (instancetype)initWithCentralIcon:(SBIcon *)icon layout:(STKGroupLayout *)layout;
- (instancetype)initWithDictionary:(NSDictionary *)repr;

@property (nonatomic, retain) SBIcon *centralIcon;
@property (nonatomic, readonly) STKGroupLayout *layout;
@property (nonatomic, readonly) STKGroupLayout *placeholderLayout;
@property (nonatomic, readonly) NSDictionary *dictionaryRepresentation;
@property (nonatomic, readonly) BOOL hasPlaceholders;
@property (nonatomic, assign) SBIconCoordinate lastKnownCoordinate;
@property (nonatomic, readonly) BOOL empty;
@property (nonatomic, assign) STKGroupState state;

- (void)relayoutForNewCoordinate:(SBIconCoordinate)coordinate;
// Relayouts if `coordinate` != `lastKnownCoordinate`

- (void)forceRelayout;
// Relayouts because YOLO

- (void)replaceIconInSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon;
// if `icon` is an empty placeholder, it is treated as such internally 

- (void)addPlaceholders;
- (void)removePlaceholders;
- (void)finalizeState;

- (void)addObserver:(id<STKGroupObserver>)observer;
- (void)removeObserver:(id<STKGroupObserver>)observer;

@end

@protocol STKGroupObserver <NSObject>
@optional
- (void)group:(STKGroup *)group removedIcon:(SBIcon *)icon inSlot:(STKGroupSlot)slot;
- (void)group:(STKGroup *)group replacedIcon:(SBIcon *)replacedIcon inSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon;
- (void)groupDidRelayout:(STKGroup *)group;
- (void)groupDidAddPlaceholders:(STKGroup *)group;
- (void)groupWillRemovePlaceholders:(STKGroup *)group;
- (void)groupDidRemovePlaceholders:(STKGroup *)group;
- (void)groupDidFinalizeState:(STKGroup *)group;
@end

