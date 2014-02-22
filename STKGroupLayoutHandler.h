#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>
#import "STKConstants.h"

#define STKCoordinateIsValid(_coord) ((_coord.col < 1000) && (_coord.row < 1000))

@class STKGroupLayout, SBIcon;
@interface STKGroupLayoutHandler : NSObject

// Set the exact position by OR'ing the different values in the enum
// It will just explode in your face if you try to pull crap.
// I mean it.
+ (STKGroupLayout *)layoutForIcons:(NSArray *)icons aroundIconAtLocation:(STKLocation)location;

+ (STKGroupLayout *)correctLayoutForGroupIfNecessary:(STKGroup *)group;

// Returns an STKGroupLayout object whose properties contain SBIcons to be faded out when the new icons are coming in
// This, is pure magic.
+ (STKGroupLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)icon usingLayout:(STKGroupLayout *)layout;

// `layout`: appearing layout
// `provider`: block that returns a CGRect for the icon at index `idx` in `layout[STKPositionTop]`.
// The frame should be converted to the coordinate system of the current root icon list.
+ (STKGroupLayout *)layoutForIconsToHideAboveDockedIcon:(SBIcon *)centralIcon
                                            usingLayout:(STKGroupLayout *)layout
                                    targetFrameProvider:(CGRect(^)(NSUInteger idx))provider;

+ (SBIconCoordinate)coordinateForIcon:(SBIcon *)icon;
+ (STKLocation)locationForIcon:(SBIcon *)icon;

// Returns a layout containing four id<NSObject> to indicate where the icons would go.
+ (STKGroupLayout *)emptyLayoutForIconAtLocation:(STKLocation)location;

// Returns a STKGroupLayout instance with STKPlaceholderIcons to indicate empty spaces in the group
+ (STKGroupLayout *)placeholderLayoutForGroup:(STKGroup *)group;

@end
