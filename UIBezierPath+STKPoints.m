/*
 Erica Sadun, http://ericasadun.com
 iPhone Developer's Cookbook, 6.x Edition
 BSD License, Use at your own risk
 */

#import "UIBezierPath+STKPoints.h"
#import <objc/runtime.h>

#define POINTSTRING(_CGPOINT_) (NSStringFromCGPoint(_CGPOINT_))
#define VALUE(_INDEX_) [NSValue valueWithCGPoint:points[_INDEX_]]
#define POINT(_INDEX_) [(NSValue *)[points objectAtIndex:_INDEX_] CGPointValue]

#define G_IVAR(_NAME_) objc_getAssociatedObject(self, @selector(_NAME_))
#define S_IVAR(_NAME_, _OBJ_) objc_setAssociatedObject(self, @selector(_NAME_), _OBJ_, OBJC_ASSOCIATION_ASSIGN)

// Return distance between two points
static float distance(CGPoint p1, CGPoint p2)
{
    float dx = p2.x - p1.x;
    float dy = p2.y - p1.y;

    return sqrt(dx*dx + dy*dy);
}

@implementation UIBezierPath (STKPoints)
void STKGetPointsFromBezier(void *info, const CGPathElement *element)
{
    NSMutableArray *bezierPoints = (NSMutableArray *)info;
    CGPathElementType type = element->type;
    CGPoint *points = element->points;
    if (type != kCGPathElementCloseSubpath)
    {
        if ((type == kCGPathElementAddLineToPoint) ||
            (type == kCGPathElementMoveToPoint))
            [bezierPoints addObject:VALUE(0)];
        else if (type == kCGPathElementAddQuadCurveToPoint)
            [bezierPoints addObject:VALUE(1)];
        else if (type == kCGPathElementAddCurveToPoint)
            [bezierPoints addObject:VALUE(2)];
    }
}

- (NSArray *)stk_points
{
    NSMutableArray *points = G_IVAR(_points);
    if (!points) {
        points = [NSMutableArray array];
        CGPathApply(self.CGPath, (void *)points, STKGetPointsFromBezier);

        S_IVAR(_points, [points retain]);
    }

    return points;
}

- (CGFloat)stk_length
{
    NSArray *points = [self stk_points];
    float totalPointLength = 0.0f;
    for (int i = 1; i < points.count; i++)
        totalPointLength += distance(POINT(i), POINT(i-1));
    return totalPointLength;
}

- (NSArray *)stk_pointPercentArray
{
    NSMutableArray *pointPercentArray = G_IVAR(_pointPercentArray);
    if (!pointPercentArray) {
        // Use total length to calculate the percent of path consumed at each control point
        NSArray *points = [self stk_points];
        int pointCount = points.count;
        
        float totalPointLength = [self stk_length];
        float distanceTravelled = 0.0f;
        
        NSMutableArray *pointPercentArray = [NSMutableArray array];
        [pointPercentArray addObject:@0.0];
        
        for (int i = 1; i < pointCount; i++)
        {
            distanceTravelled += distance(POINT(i), POINT(i-1));
            [pointPercentArray addObject:[NSNumber numberWithFloat:(distanceTravelled / totalPointLength)]];
        }

        // Add a final item just to stop with. Probably not needed.
        [pointPercentArray addObject:[NSNumber numberWithFloat:1.1f]]; // 110%

        S_IVAR(_pointPercentArray, [pointPercentArray retain]);
    }
    
    return pointPercentArray;
}

- (CGPoint)stk_pointAtPercent:(CGFloat)percent withSlope:(CGPoint *)slope
{
    NSArray *points = [self stk_points];
    NSArray *percentArray = [self stk_pointPercentArray];
    NSLog(@"%@", points);
    CFIndex lastPointIndex = points.count - 1;
    
    if (!points.count)
        return CGPointZero;
    
    // Check for 0% and 100%
    if (percent <= 0.0f) return POINT(0);
    if (percent >= 1.0f) return POINT(lastPointIndex);

    // Find a corresponding pair of points in the path
    CFIndex index = 1;
    while ((index < percentArray.count) &&
           (percent > ((NSNumber *)percentArray[index]).floatValue)) {
        index++;
    }
    
    // This should not happen.
    if (index > lastPointIndex) return POINT(lastPointIndex);
    
    // Calculate the intermediate distance between the two points
    CGPoint point1 = POINT(index -1);
    CGPoint point2 = POINT(index);
    
    float percent1 = [[percentArray objectAtIndex:index - 1] floatValue];
    float percent2 = [[percentArray objectAtIndex:index] floatValue];
    float percentOffset = (percent - percent1) / (percent2 - percent1);
    
    float dx = point2.x - point1.x;
    float dy = point2.y - point1.y;
    
    // Store dy, dx for retrieving arctan
    if (slope) *slope = CGPointMake(dx, dy);
    
    // Calculate new point
    CGFloat newX = point1.x + (percentOffset * dx);
    CGFloat newY = point1.y + (percentOffset * dy);
    CGPoint targetPoint = CGPointMake(newX, newY);
    
    return targetPoint;
}


- (void)stk_resetPoints
{
    [G_IVAR(_points) release];
    [G_IVAR(_pointsPercentArray) release];

    S_IVAR(_points, nil);
    S_IVAR(_pointsPercentArray, nil);
}

@end
