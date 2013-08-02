/*
 Erica Sadun, http://ericasadun.com
 iPhone Developer's Cookbook, 6.x Edition
 BSD License, Use at your own risk
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface UIBezierPath (STKPoints)

- (CGPoint)stk_pointAtPercent:(CGFloat)percent withSlope:(CGPoint *)slope;

// Call this method whenever the path is modified to make sure you receive updated data from the above method
- (void)stk_resetPoints;

@end