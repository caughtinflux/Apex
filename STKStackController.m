#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

#import "STKStackController.h"
#import "STKConstants.h"
#import "STKStack.h"
#import "STKPreferences.h"

#if !defined CLASS
#define CLASS(_cls) objc_getClass(#_cls)
#endif

@interface STKStackController ()
{
    NSMutableArray *_iconsToShow;
    NSMutableArray *_iconsToHide;
    STKStack *_activeStack;
}

- (void)_addGrabbersToIconView:(SBIconView *)iconView;
- (void)_removeGrabbersFromIconView:(SBIconView *)iconView;

- (NSMutableArray *)_iconsToShowOnClose;
- (NSMutableArray *)_iconsToHideOnClose;
- (void)_processIconsPostStackClose;

@end

#define ICONVIEW(_icon) [[CLASS(SBIconViewMap) homescreenMap] mappedIconViewForIcon:_icon]

@implementation STKStackController

+ (instancetype)sharedInstance
{
    static id _sharedInstance;

    dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        _sharedInstance = [[self alloc] init];
    });

    return _sharedInstance;
}

- (void)createStackForIconView:(SBIconView *)iconView
{

}

- (void)removeStackFromIconView:(SBIconView *)iconView
{

}


#pragma mark - Private Methods
- (NSMutableArray *)_iconsToShowOnClose
{
    if (!_iconsToShow) {
        _iconsToShow = [NSMutableArray new];
    }

    return _iconsToShow;
}

- (NSMutableArray *)_iconsToHideOnClose
{
    if (!_iconsToHide) {
        _iconsToHide = [NSMutableArray new];
    }

    return _iconsToHide;
}

- (void)_processIconsPostStackClose
{
    SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];
    [model _postIconVisibilityChangedNotificationShowing:_iconsToShow hiding:_iconsToHide];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:STKRecalculateLayoutsNotification object:nil userInfo:nil];
    
    [_iconsToShow release];
    _iconsToShow = nil;
    [_iconsToHide release];
    _iconsToHide = nil;
}


#pragma mark - Stack Delegate
- (void)stackDidUpdateState:(STKStack *)stack
{

}

- (void)stack:(STKStack *)stack didAddIcon:(SBIcon *)addedIcon removingIcon:(SBIcon *)removedIcon atPosition:(STKLayoutPosition)position index:(NSUInteger)idx
{
    if (stack.isEmpty) {
        [[STKPreferences sharedPreferences] removeLayoutForIcon:stack.centralIcon];
        if (!stack.showsPreview) {
            [self _removeGrabbersFromIconView:ICONVIEW(stack.centralIcon)];
        }
    }
    else {
        // `addedIcon` can be an icon inside another stack
        SBIcon *centralIconForOtherStack = [[STKPreferences sharedPreferences] centralIconForIcon:addedIcon];
        if (centralIconForOtherStack) {
            SBIconView *otherView = ICONVIEW(centralIconForOtherStack);
            STKStack *otherStack = [self stackForView:otherView];
            if (otherStack != stack || !otherStack) {
                [[STKPreferences sharedPreferences] removeCachedLayoutForIcon:centralIconForOtherStack];

                if (otherStack) {
                    [otherStack removeIconFromAppearingIcons:addedIcon];

                    if (otherStack.isEmpty) {
                        [[STKPreferences sharedPreferences] removeLayoutForIcon:otherStack.centralIcon];
                        [otherStack cleanupView];
                        ICONVIEW(otherStack.centralIcon).transform = CGAffineTransformMakeScale(1.f, 1.f);
                    }
                    else {
                        [otherStack saveLayoutToFile:[STKPreferences layoutPathForIcon:otherStack.centralIcon]];
                    }
                }
                else {
                    // Other stack is nil, so manually do the work
                    NSDictionary *cachedLayout = [[STKPreferences sharedPreferences] cachedLayoutDictForIcon:centralIconForOtherStack];

                    STKIconLayout *layout = [STKIconLayout layoutWithDictionary:cachedLayout];
                    [layout removeIcon:addedIcon];

                    if ([layout allIcons].count > 0) {
                        [STKPreferences saveLayout:layout forIcon:centralIconForOtherStack];
                    }
                    else {
                        [[STKPreferences sharedPreferences] removeLayoutForIcon:centralIconForOtherStack];
                    }
                    [self createStackForIconView:otherView];
                }

            }
        }
        if (!stack.showsPreview) {
            [self _addGrabbersToIconView:ICONVIEW(stack.centralIcon)];
        }

        NSString *layoutPath = [STKPreferences layoutPathForIcon:stack.centralIcon];
        [stack saveLayoutToFile:layoutPath];
    }

    [[STKPreferences sharedPreferences] reloadPreferences];

    if (ICON_IS_IN_STACK(addedIcon)) {
        [[self _iconsToHideOnClose] addObject:addedIcon];
    }
    if (!ICON_IS_IN_STACK(removedIcon)) {
        [[self _iconsToShowOnClose] addObject:removedIcon];
    }
}

@end
