#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

#import "STKStackController.h"
#import "STKConstants.h"
#import "STKStack.h"
#import "STKPreferences.h"

#if !defined CLASS
#define CLASS(_cls) objc_getClass(#_cls)
#endif

#define ICONVIEW(_icon) [[CLASS(SBIconViewMap) homescreenMap] mappedIconViewForIcon:_icon]
#define IS_VALID_LOCATION(_loc) (_loc == SBIconViewLocationHomeScreen || _loc == SBIconViewLocationDock)

static SEL __stackKey;
static SEL __recognizerKey;
static SEL __topGrabberKey;
static SEL __bottomGrabberKey;

static void STKPiratedAlertCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags);

@interface STKStackController ()
{
    NSMutableArray *_iconsToShow;
    NSMutableArray *_iconsToHide;
}
- (NSMutableArray *)_iconsToShowOnClose;
- (NSMutableArray *)_iconsToHideOnClose;
- (void)_processIconsPostStackClose;
- (void)_panned:(UIPanGestureRecognizer *)recognizer;
- (void)_doubleTapped:(UITapGestureRecognizer *)recognizer;
@end

@implementation STKStackController

+ (instancetype)sharedInstance
{
    static STKStackController *_sharedInstance;
    static dispatch_once_t predicate = 0;
    dispatch_once(&predicate, ^{
        _sharedInstance = [[self alloc] init];

        __stackKey = @selector(apexStack);
        __recognizerKey = @selector(apexRecognizer);
        __topGrabberKey = @selector(apexTopGrabber);
        __bottomGrabberKey = @selector(apexBottomGrabber);

        [[NSNotificationCenter defaultCenter] addObserver:_sharedInstance selector:@selector(_prefsChanged:) name:STKPreferencesChangedNotification object:nil];
    });

    return _sharedInstance;
}

- (void)createOrRemoveStackForIconView:(SBIconView *)iconView
{
    SBIcon *icon = iconView.icon;
    UIView *superview = iconView.superview;
    BOOL isInInfinifolder = ([superview isKindOfClass:[UIScrollView class]] && [superview.superview isKindOfClass:CLASS(SBFolderIconListView)]);

    if ([self stackForIconView:iconView]) {
        return;
    }
    if (!icon ||
        !IS_VALID_LOCATION(iconView.location) || (!superview && ![iconView isInDock]) || [superview isKindOfClass:CLASS(SBFolderIconListView)] || isInInfinifolder || 
        [[CLASS(SBIconController) sharedInstance] grabbedIcon] == icon ||
        ![icon isLeafIcon] || [icon isDownloadingIcon] || 
        [[STKPreferences sharedPreferences] iconIsInStack:icon]) {
        // Don't add recognizer to icons in the stack already
        // In the switcher, -setIcon: is called to change the icon, but doesn't change the icon view, so cleanup.
        if ([self stackForIconView:iconView]) {
            [self removeStackFromIconView:iconView];
        }
    }
    else {
        [self createStackForIconView:iconView];
    }
}

#pragma mark - Stack Creation
- (void)createStackForIconView:(SBIconView *)iconView
{
    [self addRecognizerToIconView:iconView];
    STKStack *stack = [self stackForIconView:iconView];

    if (!stack) {
        NSString *layoutPath = [STKPreferences layoutPathForIcon:iconView.icon];
        if (ICON_HAS_STACK(iconView.icon)) {

            NSDictionary *cachedLayout = [[STKPreferences sharedPreferences] cachedLayoutDictForIcon:iconView.icon];
            if (cachedLayout) {
                stack = [[STKStack alloc] initWithCentralIcon:iconView.icon withCustomLayout:cachedLayout];
                if (stack.layoutDiffersFromFile) {
                    [STKPreferences saveLayout:stack.appearingIconLayout forIcon:stack.centralIcon];
                }
            }
            else {
                stack = [[STKStack alloc] initWithContentsOfFile:layoutPath];
                if (stack.layoutDiffersFromFile) {
                    [STKPreferences saveLayout:stack.appearingIconLayout forIcon:stack.centralIcon];
                }
                else if (!stack) {
                    // Control should not get here, since
                    // we are already checking if the layout is invalid
                    NSArray *stackIcons = [[STKPreferences sharedPreferences] stackIconsForIcon:iconView.icon];
                    stack = [[STKStack alloc] initWithCentralIcon:iconView.icon stackIcons:stackIcons];
                    if (![stack isEmpty]) {
                        [STKPreferences saveLayout:stack.appearingIconLayout forIcon:stack.centralIcon];
                    }
                }
            }              
        }
        else {            
            stack = [[STKStack alloc] initWithCentralIcon:iconView.icon stackIcons:nil];
        }

        stack.showsPreview = [STKPreferences sharedPreferences].previewEnabled;
        objc_setAssociatedObject(iconView, __stackKey, stack, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stack release];
    }

    if (stack.isEmpty == NO && stack.showsPreview) {
        [stack setupPreview];
        [stack recalculateLayouts];
    }

    CGFloat scale = (stack.isEmpty || !stack.showsPreview ? 1.f : kCentralIconPreviewScale);
    iconView.iconImageView.transform = CGAffineTransformMakeScale(scale, scale);

    // Add grabber images if necessary
    if (stack && !stack.showsPreview && !stack.isEmpty && ![[STKPreferences sharedPreferences] shouldHideGrabbers]) {
        [self addGrabbersToIconView:iconView];
        NSArray *grabbers = [self grabberViewsForIconView:iconView];
        if (grabbers.count == 2) {
            stack.topGrabberView = grabbers[0];
            stack.bottomGrabberView = grabbers[1];
        }
    }

    stack.delegate = self;
}

#pragma mark - Stack Removal
- (void)removeStackFromIconView:(SBIconView *)iconView
{
    [[self stackForIconView:iconView] cleanupView];
    iconView.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
    objc_setAssociatedObject(iconView, __stackKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self removeRecognizerFromIconView:iconView];
    [self removeGrabbersFromIconView:iconView];
}

#pragma mark - Pan Recognizer Handling
- (void)addRecognizerToIconView:(SBIconView *)iconView
{
    Class recognizerClass = (([STKPreferences sharedPreferences].activationMode == STKActivationModeDoubleTap) ? [UITapGestureRecognizer class] : [UIPanGestureRecognizer class]);
    UIGestureRecognizer *recognizer = objc_getAssociatedObject(iconView, __recognizerKey);
    if (!iconView || recognizer) {
        return;
    }
    recognizer = [[[recognizerClass alloc] init] autorelease];
    if ([recognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        [recognizer addTarget:self action:@selector(_panned:)];
    }
    else {
        [recognizer addTarget:self action:@selector(_doubleTapped:)];
        ((UITapGestureRecognizer *)recognizer).numberOfTapsRequired = 2;
    }
    [iconView addGestureRecognizer:recognizer];
    objc_setAssociatedObject(iconView, __recognizerKey, recognizer, OBJC_ASSOCIATION_ASSIGN);
    recognizer.delegate = self;
}

- (void)removeRecognizerFromIconView:(SBIconView *)iconView
{
    UIGestureRecognizer *recognizer = objc_getAssociatedObject(iconView, __recognizerKey);
    [iconView removeGestureRecognizer:recognizer];
    objc_setAssociatedObject(iconView, __recognizerKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - Grabbers
- (void)addGrabbersToIconView:(SBIconView *)iconView
{
    if ([STKPreferences sharedPreferences].shouldHideGrabbers || !iconView) {
        return;
    }
    UIImageView *topView = objc_getAssociatedObject(iconView, __topGrabberKey);
    if (!topView) {
        topView = [[[UIImageView alloc] initWithImage:UIIMAGE_NAMED(@"TopGrabber")] autorelease];
        topView.center = (CGPoint){iconView.iconImageView.center.x, (iconView.iconImageView.frame.origin.y)};
        [iconView insertSubview:topView atIndex:0];
        objc_setAssociatedObject(iconView, __topGrabberKey, topView, OBJC_ASSOCIATION_ASSIGN);
    }
    UIImageView *bottomView = objc_getAssociatedObject(iconView, __bottomGrabberKey);
    if (!bottomView) {
        bottomView = [[[UIImageView alloc] initWithImage:UIIMAGE_NAMED(@"BottomGrabber")] autorelease];
        bottomView.center = (CGPoint){iconView.iconImageView.center.x, (CGRectGetMaxY(iconView.iconImageView.frame) - 1)};
        [iconView insertSubview:bottomView belowSubview:iconView.iconImageView];
        objc_setAssociatedObject(iconView, __bottomGrabberKey, bottomView, OBJC_ASSOCIATION_ASSIGN);
    }
}

- (void)removeGrabbersFromIconView:(SBIconView *)iconView
{
    [(UIView *)objc_getAssociatedObject(iconView, __topGrabberKey) removeFromSuperview];
    [(UIView *)objc_getAssociatedObject(iconView, __bottomGrabberKey) removeFromSuperview];  
    objc_setAssociatedObject(iconView, __topGrabberKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(iconView, __bottomGrabberKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - Stack Info Getters? Wut.
- (STKStack *)stackForIconView:(SBIconView *)iconView
{
    return objc_getAssociatedObject(iconView, __stackKey);
}

- (NSArray *)grabberViewsForIconView:(SBIconView *)iconView
{
    NSMutableArray *grabbers = [NSMutableArray array];
    UIView *topGrabber = objc_getAssociatedObject(iconView, __topGrabberKey);
    UIView *bottomGrabber = objc_getAssociatedObject(iconView, __bottomGrabberKey);

    if (topGrabber) {
        [grabbers addObject:topGrabber];
    }
    if (bottomGrabber) {
        [grabbers addObject:bottomGrabber];
    }

    return [[grabbers copy] autorelease];
}

- (void)closeActiveStack
{
    [self.activeStack closeWithCompletionHandler:^{ [self stackClosedByGesture:self.activeStack]; }];
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
    if (!_iconsToHide && !_iconsToShow) {
        return;
    }
    SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];
    [model _postIconVisibilityChangedNotificationShowing:_iconsToShow hiding:_iconsToHide];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:STKRecalculateLayoutsNotification object:nil userInfo:nil];
    
    [_iconsToShow release];
    _iconsToShow = nil;
    [_iconsToHide release];
    _iconsToHide = nil;
}

#pragma mark - Prefs Update
- (void)_prefsChanged:(NSNotification *)notification
{
    BOOL previewEnabled = [STKPreferences sharedPreferences].previewEnabled;
    BOOL shouldHideGrabbers = [STKPreferences sharedPreferences].shouldHideGrabbers;
    void (^aBlock)(SBIconView *iconView) = ^(SBIconView *iconView) {
        STKStack *stack = [self stackForIconView:iconView];
        if (!iconView || !stack) {
            return;
        }
        // Re-add the recognizers, so if the activation mode has changed, it would've been updated
        [self removeRecognizerFromIconView:iconView];
        [self addRecognizerToIconView:iconView];

        if (!stack.isEmpty) {
            if (previewEnabled || shouldHideGrabbers) { // Removal of grabber images will be the same in either case 
                if (previewEnabled) {
                    // But only if preview is enabled should be change the scale
                    iconView.iconImageView.transform = CGAffineTransformMakeScale(kCentralIconPreviewScale, kCentralIconPreviewScale);
                }
                [self removeGrabbersFromIconView:iconView];
                stack.topGrabberView = nil;
                stack.bottomGrabberView = nil;
            }
            else if (!previewEnabled && !shouldHideGrabbers) {
                // If preview is disabled and we shouldn't hide the grabbers, add 'em.
                iconView.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
                [self addGrabbersToIconView:iconView];
                NSArray *grabberViews = [self grabberViewsForIconView:iconView];
                stack.topGrabberView = grabberViews[0];
                stack.bottomGrabberView = grabberViews[1];
            }
        }
        stack.showsPreview = previewEnabled;
    };
    for (SBIconListView *listView in [[CLASS(SBIconController) sharedInstance] valueForKey:@"_rootIconLists"]){
        [listView makeIconViewsPerformBlock:aBlock];
    }
    SBIconListView *folderListView = (SBIconListView *)[[CLASS(SBIconController) sharedInstance] currentFolderIconList];
    if ([folderListView isKindOfClass:CLASS(FEIconListView)]) {
        [folderListView makeIconViewsPerformBlock:aBlock];
    }
    [[[CLASS(SBIconController) sharedInstance] dock] makeIconViewsPerformBlock:aBlock];
}


#pragma mark - Activation Recognizer Handling
#define kBandingFactor  0.1 // The factor by which the distance should be multiplied to simulate the rubber banding effect
- (void)_panned:(UIPanGestureRecognizer *)sender
{
    static BOOL cancelledPanRecognizer;
    static BOOL hasVerticalIcons;
    static BOOL isUpwardSwipe;

    SBIconView *iconView = (SBIconView *)sender.view;
    UIScrollView *view = (UIScrollView *)[STKListViewForIcon(iconView.icon) superview];
    STKStack *stack = [self stackForIconView:iconView];
    STKStack *activeStack = [STKStackController sharedInstance].activeStack;

    if (!IS_VALID_LOCATION(iconView.location)) {
        cancelledPanRecognizer = YES;
        [self removeStackFromIconView:iconView];
        return;
    }
    if (stack.isExpanded || (activeStack != nil && activeStack != stack)) {
        cancelledPanRecognizer = YES;
        return;
    }
    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
            CGPoint translation = [sender translationInView:view];
            isUpwardSwipe = ([sender velocityInView:view].y < 0);
            BOOL isHorizontalSwipe = !((fabsf(translation.x / translation.y) < 5.0) || translation.x == 0);

            BOOL isUpwardSwipeInSwipeDownMode = (([STKPreferences sharedPreferences].activationMode == STKActivationModeSwipeDown) && isUpwardSwipe);
            BOOL isDownwardSwipeInSwipeUpMode = (([STKPreferences sharedPreferences].activationMode == STKActivationModeSwipeUp) && !isUpwardSwipe);
            
            if (isHorizontalSwipe || isUpwardSwipeInSwipeDownMode || isDownwardSwipeInSwipeUpMode) {
                cancelledPanRecognizer = YES;
                return;
            }
            if ([view isKindOfClass:[UIScrollView class]]) {
                // Turn off scrolling
                view.scrollEnabled = NO;
            }
            // Update the target distance based on icons positions when the pan begins
            // This way, we can be sure that the icons are indeed in the required location 
            STKUpdateTargetDistanceInListView([[CLASS(SBIconController) sharedInstance] currentRootIconList], [iconView isInDock]);
            [stack setupViewIfNecessary];

            self.activeStack = stack;
            [stack touchesBegan];

            hasVerticalIcons = ([stack.appearingIconLayout iconsForPosition:STKLayoutPositionTop].count > 0) || ([stack.appearingIconLayout iconsForPosition:STKLayoutPositionBottom].count > 0);
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (([view isKindOfClass:[UIScrollView class]] && view.isDragging) || cancelledPanRecognizer) {
                cancelledPanRecognizer = YES;
                return;
            }
            CGFloat change = [sender translationInView:view].y;
            if (isUpwardSwipe) {
                change = -change;
            }
            CGFloat targetDistance = STKGetCurrentTargetDistance();
            if (!hasVerticalIcons) {
                targetDistance *= stack.distanceRatio;
            }
            if ((change > 0) && (stack.currentIconDistance >= targetDistance)) {
                // Factor this down to simulate elasticity when the icons have reached their target locations
                // The stack allows the icons to go beyond their targets for a little distance
                change *= kBandingFactor;
            }
            [stack touchesDraggedForDistance:change];
            [sender setTranslation:CGPointZero inView:view];
            break;
        }
        case UIGestureRecognizerStateEnded: {
            if (cancelledPanRecognizer == NO) {
                [stack touchesEnded:^{
                    if (stack.isExpanded) {
                        self.activeStack = stack;   
                    }
                    else {
                        self.activeStack = nil;
                        [stack.centralIcon noteBadgeDidChange];
                    }
                }];
            }
            /*********************************************************************************************
            ***************************    NOTE THE LACK OF A break;   ***********************************
            *********************************************************************************************/
        }
        default: {
            cancelledPanRecognizer = NO; 
            isUpwardSwipe = NO; 
            hasVerticalIcons = NO; 
            if ([view isKindOfClass:[UIScrollView class]]) {
                view.scrollEnabled = YES;
            }
            break;
        }
    }
}

- (void)_doubleTapped:(UITapGestureRecognizer *)recognizer
{
    SBIconView *iconView = (SBIconView *)recognizer.view;
    STKStack *stack = [self stackForIconView:iconView];
    STKStack *activeStack = self.activeStack;
    if (activeStack) {
        return;
    }
    self.activeStack = stack;
    [stack touchesBegan];
    [stack open];
}

#pragma mark - Gesture Recognizer Delegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    BOOL ret = YES;
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        if (self.activeStack) {
            ret = (otherGestureRecognizer == [[CLASS(SBIconController) sharedInstance] scrollView].panGestureRecognizer);
        }
        else {
            ret = ([otherGestureRecognizer isMemberOfClass:[UISwipeGestureRecognizer class]] ||
                  (otherGestureRecognizer == [[CLASS(SBIconController) sharedInstance] scrollView].panGestureRecognizer) ||
                  ([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]] && [otherGestureRecognizer.view.superview isKindOfClass:CLASS(FEGridFolderView)]));
        }
    }
    return ret;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer
{
    STKStack *stack = [self stackForIconView:(SBIconView *)recognizer.view];
    BOOL lockLayoutsForStack = (stack.isEmpty && [STKPreferences sharedPreferences].layoutsAreLocked);
    return ([[CLASS(SBIconController) sharedInstance] isEditing] ? NO : !lockLayoutsForStack);
}

#pragma mark - Stack Delegate
- (void)stack:(STKStack *)stack didReceiveTapOnIconView:(SBIconView *)iconView
{
    [iconView.icon launch];
    if ([[STKPreferences sharedPreferences] shouldCloseOnLaunch]) {
        [stack close];
        self.activeStack = nil;
    }
}

- (void)stack:(STKStack *)stack didReceiveTapOnPlaceholderIconView:(SBIconView *)iconView
{
    if (IS_PIRATED() && [[STKPreferences sharedPreferences] identifiersForIconsWithStack].count >= 3 && stack.isEmpty) {
        NSDictionary *fields = @{(id)kCFUserNotificationAlertHeaderKey: @"Apex",
                                 (id)kCFUserNotificationAlertMessageKey: @"You seem to be using an unofficial copy of Apex (╯°□°）╯︵ ┻━┻\nPlease purchase it from Cydia to use more than three stacks, and to receive support.",
                                 (id)kCFUserNotificationDefaultButtonTitleKey: @"Open Cydia",
                                 (id)kCFUserNotificationAlternateButtonTitleKey: @"Dismiss"};

        SInt32 error = 0;
        CFUserNotificationRef notificationRef = CFUserNotificationCreate(kCFAllocatorDefault, 0, kCFUserNotificationNoteAlertLevel, &error, (CFDictionaryRef)fields);
        CFRunLoopSourceRef runLoopSource = CFUserNotificationCreateRunLoopSource(kCFAllocatorDefault, notificationRef, STKPiratedAlertCallback, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
    }
    else {
        [stack showSelectionViewOnIconView:iconView];
    }
}

- (void)stackClosedByGesture:(STKStack *)stack
{
    [self _processIconsPostStackClose];
    if (stack.isEmpty || !stack.showsPreview) {
        [stack cleanupView];
    }
    self.activeStack = nil;
    [stack.centralIcon noteBadgeDidChange];
}

- (void)stackDidChangeLayout:(STKStack *)stack
{
    [self stack:stack didAddIcon:nil removingIcon:nil atPosition:0 index:0];
    [stack.centralIcon noteBadgeDidChange];
}

- (void)stack:(STKStack *)stack didAddIcon:(SBIcon *)addedIcon removingIcon:(SBIcon *)removedIcon atPosition:(STKLayoutPosition)position index:(NSUInteger)idx
{
    if (stack.isEmpty) {
        [[STKPreferences sharedPreferences] removeLayoutForIcon:stack.centralIcon];
        if (!stack.showsPreview) {
            [self removeGrabbersFromIconView:ICONVIEW(stack.centralIcon)];
        }
    }
    else {
        // `addedIcon` can be an icon inside another stack
        SBIcon *centralIconForOtherStack = [[STKPreferences sharedPreferences] centralIconForIcon:addedIcon];
        if (centralIconForOtherStack) {
            SBIconView *otherView = ICONVIEW(centralIconForOtherStack);
            STKStack *otherStack = [self stackForIconView:otherView];
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
                        [STKPreferences saveLayout:otherStack.appearingIconLayout forIcon:otherStack.centralIcon];
                    }
                }
                else { // otherStack == nil
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
            [centralIconForOtherStack noteBadgeDidChange];
        }
        if (!stack.showsPreview) {
            [self addGrabbersToIconView:ICONVIEW(stack.centralIcon)];
        }
        [STKPreferences saveLayout:stack.appearingIconLayout forIcon:stack.centralIcon];
    }
    [[STKPreferences sharedPreferences] reloadPreferences];
    if (ICON_IS_IN_STACK(addedIcon)) {
        [[self _iconsToHideOnClose] addObject:addedIcon];
    }
    if (removedIcon && !ICON_IS_IN_STACK(removedIcon)) {
        [[self _iconsToShowOnClose] addObject:removedIcon];
    }
    [stack.centralIcon noteBadgeDidChange];
}

static void STKPiratedAlertCallback(CFUserNotificationRef userNotification, CFOptionFlags responseFlags)
{
    if ((responseFlags & 0x3) == kCFUserNotificationDefaultResponse) {
        // Open settings to custom bundle
        [(SpringBoard *)[UIApplication sharedApplication] applicationOpenURL:[NSURL URLWithString:@"cydia://package/com.a3tweaks.apex"] publicURLsOnly:NO];
    }
    CFRelease(userNotification);
}

@end
