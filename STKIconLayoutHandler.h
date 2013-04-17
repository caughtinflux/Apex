#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "STKConstants.h"

typedef enum {
    STKPositionTouchingTop    = 0x2,
    STKPositionTouchingBottom = 0x4,
    STKPositionTouchingLeft   = 0x8,
    STKPositionTouchingRight  = 0x16,
    STKPositionDock           = 0x32
} STKPosition;

typedef NSUInteger STKPositionMask;

typedef struct {
	NSUInteger xPos;
	NSUInteger yPos;
	NSUInteger index;
} STKIconCoordinates;

@class STKIconLayout, SBIcon;
@interface STKIconLayoutHandler : NSObject

// Set the exact position by OR'ing the different values in the enum
// It will just explode in your face if you do rubbish like setting both TouchingTop and TouchingBottom
// I mean it.
- (STKIconLayout *)layoutForIcons:(NSArray *)icons aroundIconAtPosition:(STKPositionMask)position;

// Returns an STKIconLayout object whose properties contain SBIcons to be faded out when the new icons are coming in
// This, is plain magic.
- (STKIconLayout *)layoutForIconsToDisplaceAroundIcon:(SBIcon *)icon usingLayout:(STKIconLayout *)layout;
- (STKIconCoordinates *)copyCoordinatesForIcon:(SBIcon *)icon withOrientation:(UIInterfaceOrientation)orientation;

@end
