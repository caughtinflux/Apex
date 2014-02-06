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
@property (nonatomic, readonly) BOOL empty;
@property (nonatomic, assign) STKGroupState state;

- (void)relayoutForNewCoordinate:(SBIconCoordinate)coordinate;
// Relayouts if `coordinate` != `lastKnownCoordinate`

- (void)replaceIconInSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon;
- (void)removeIconInSlot:(STKGroupSlot)slot;

- (void)addObserver:(id<STKGroupObserver>)observer;
- (void)removeObserver:(id<STKGroupObserver>)observer;

@end

@protocol STKGroupObserver <NSObject>
@optional
- (void)group:(STKGroup *)group didReplaceIcon:(SBIcon *)replacedIcon inSlot:(STKGroupSlot)slot withIcon:(SBIcon *)icon;
- (void)groupDidRelayout:(STKGroup *)group;
@end
