#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

typedef NS_OPTIONS(NSUInteger, STKLocation) {
    STKLocationRegular        = 0,
    STKLocationTouchingTop    = 1 << 0,
    STKLocationTouchingBottom = 1 << 1,
    STKLocationTouchingLeft   = 1 << 2,
    STKLocationTouchingRight  = 1 << 3,
    STKLocationDock           = 1 << 4
};

#define STKPositionMasksEqual(_a, _b) ( ((a & STKPositionRegular) == (b & STKPositionRegular)) && \
									    ((a & STKPositionTouchingTop) == (b & STKPositionTouchingTop)) && ((a & STKPositionTouchingBottom) == (b & STKPositionTouchingBottom)) && \
									    ((a & STKPositionTouchingLeft) == (b & STKPositionTouchingLeft)) && ((a & STKPositionTouchingRight) == (b & STKPositionTouchingRight)) && \
									    ((a & STKPositionDock) == (b & STKPositionDock)) )

#define STKCoordinateIsValid(_coords) (!(_coords.col > 1000) && !(_coords.row > 1000))

@class STKGroupLayout, SBIcon;
@interface STKGroupLayoutHandler : NSObject

// Set the exact position by OR'ing the different values in the enum
// It will just explode in your face if you try to pull crap.
// I mean it.
+ (STKGroupLayout *)layoutForIcons:(NSArray *)icons aroundIconAtLocation:(STKLocation)location;

+ (BOOL)layout:(STKGroupLayout *)layout requiresRelayoutForLocation:(STKLocation)location suggestedLayout:(__autoreleasing STKGroupLayout **)outLayout;

// Returns an STKGroupLayout object whose properties contain SBIcons to be faded out when the new icons are coming in
// This, is plain magic.
+ (STKGroupLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)icon usingLayout:(STKGroupLayout *)layout;
+ (SBIconCoordinate)coordinateForIcon:(SBIcon *)icon;

// Returns a layout containing four id<NSObject> to indicate where the icons would go.
+ (STKGroupLayout *)emptyLayoutForIconAtLocation:(STKLocation)location;

// Returns a STKGroupLayout instance with objects to indicate where there are empty spaces in `layout`
+ (STKGroupLayout *)layoutForPlaceholdersInLayout:(STKGroupLayout *)layout withLocation:(STKLocation)location;

@end
