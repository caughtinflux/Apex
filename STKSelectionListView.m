#import "STKSelectionListView.h"
#import "STKConstants.h"
#import "STKIconLayout.h"

#import <SpringBoard/SpringBoard.h>
#import <AppList/AppList.h>

#define G_IVAR(_name) objc_getAssociatedObject(self, @selector(_name))
#define S_IVAR(_name, _object) objc_setAssociatedObject(self, @selector(_name), _object, OBJC_ASSOCIATION_ASSIGN)

@interface STKSelectionListView ()
{
    UIScrollView *_listScrollView;
}

@end

@implementation STKSelectionListView

- (instancetype)initWithIconView:(SBIconView *)iconView inLayout:(STKIconLayout *)iconViewLayout centralIconView:(SBIconView *)centralIconView displacedIcons:(STKIconLayout *)displacedIconsLayout
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
