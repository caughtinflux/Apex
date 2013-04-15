#import "STKConstants.h"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

NSString * const STKTweakName = @"Stacks";

double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax)
{
	double ret = ((numToScale - prevMin) * (newMax - newMin)) \
			  /*-------------------------------------------------*/ /\
				      ((prevMax - prevMin) + newMin);

	return ret;
}

double STKAlphaFromDistance(double distance)
{
	// Subtract from 1 to invert the scale
	// Greater the distance, lower the alpha
	return (STKScaleNumber(distance, 0.0, 100, 0.0, 1.0));
}
