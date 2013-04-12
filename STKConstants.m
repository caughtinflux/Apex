#import "STKConstants.h"
#import <Foundation/Foundation.h>

NSString * const STKTweakName = @"Stacks";

double STKScaleNumber(double numToScale, double prevMin, double prevMax, double newMin, double newMax)
{
	// MAAAATTTTHHHHHSSSSS!!!111!!
	double ret = ((numToScale - prevMin) * (newMax - newMin)) \
			  /*-------------------------------------------------*/ /\
				      ((prevMax -prevMin) + newMin);

	return ret;
}
