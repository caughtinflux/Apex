#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"

#import <SpringBoard/SpringBoard.h>
#import <AppList/AppList.h>

#define G_IVAR(_name) objc_getAssociatedObject(self, @selector(_name))
#define S_IVAR(_name, _object) objc_setAssociatedObject(self, @selector(_name), _object, OBJC_ASSOCIATION_ASSIGN)

@interface STKSelectionView ()
{
    UIScrollView *_listScrollView;
}

@end

@implementation STKSelectionView

- (instancetype)initWithIconView:(SBIconView *)iconView
                        inLayout:(STKIconLayout *)iconViewLayout
                        position:(STKPositionMask)position
                 centralIconView:(SBIconView *)centralIconView
                  displacedIcons:(STKIconLayout *)displacedIconsLayout
{
    if ((self = [super initWithFrame:CGRectZero])) {

    }
    return self;
}

- (instancetype)init
{
    NSAssert(NO, @"***You must use one of the designated initializers");
    return nil;
}

@end
