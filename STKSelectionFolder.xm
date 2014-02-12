#import "STKSelectionFolder.h"
#import "STKConstants.h"

%subclass STKSelectionFolder : SBFolder

%new
+ (id)sharedInstance
{
    static dispatch_once_t predicate;
    static id __si;
    dispatch_once(&predicate, ^{
        __si = [[self alloc] init];
    });
    return __si;
}

- (id)init
{
    if ((self = %orig())) {
        SBIconModel *model = [(SBIconController *)[%c(SBIconController) sharedInstance] model];
        for (SBIcon *icon in [model leafIcons]) {
            if ([model isIconVisible:icon]) {
                [self addIcon:icon];
            }
        }
    }
    return self;
}

%end
