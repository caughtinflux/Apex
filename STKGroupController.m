#import "STKGroupController.h"
#import "STKConstants.h"
#import "Asphaleia.h"
#import <dlfcn.h>

#define kFullDimStrength 0.3f

@interface SBSearchGesture (ApexAdditions)
- (void)stk_setEnabled:(BOOL)enabled;
@end

NSString * NSStringFromSTKClosingEvent(STKClosingEvent event) {
    switch (event) {
        case STKClosingEventHomeButtonPress: {
            return @"STKClosingEventHomeButtonPress";
        }
        case STKClosingEventListViewScroll: {
            return @"STKClosingEventListViewScroll";
        }
        case STKClosingEventSwitcherActivation: {
            return @"STKClosingEventSwitcherActivation";
        }
        case STKClosingEventLock: {
            return @"STKClosingEventLock";
        }
    }
}

@implementation STKGroupController
{
    STKGroupView *_openGroupView;
    UIView *_listDimmingView;
    UISwipeGestureRecognizer *_closeSwipeRecognizer;
    UITapGestureRecognizer *_closeTapRecognizer;

    STKGroupSelectionAnimator *_selectionAnimator;
    STKSelectionView *_selectionView;
    STKGroupSlot _selectionSlot;

    NSMutableArray *_iconsToShow;
    NSMutableArray *_iconsToHide;

    BOOL _openGroupViewWasModified;
    BOOL _wasLongPressed;
    BOOL _hasInfiniBoard;
    BOOL _hasInfinidock;
    BOOL _hasCylinder;

    STKIconViewRecycler *_recycler;
    NSCache *_groupCache;
}

+ (instancetype)sharedController
{
    static dispatch_once_t pred;
    static id _si;
    dispatch_once(&pred, ^{
        _si = [[self alloc] init];
    });
    return _si;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _closeTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_closeOpenGroupOrSelectionView)];
        _closeSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(_closeOpenGroupOrSelectionView)];
        _closeSwipeRecognizer.direction = (UISwipeGestureRecognizerDirectionUp | UISwipeGestureRecognizerDirectionDown);
        _closeSwipeRecognizer.delegate = self;
        _closeTapRecognizer.delegate = self;

        _recycler = [[STKIconViewRecycler alloc] init];
        _groupCache = [[NSCache alloc] init];
        [_groupCache setCountLimit:200];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_prefsChanged)
                                                     name:(NSString *)STKPrefsChangedNotificationName
                                                   object:nil];
        void *handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Infiniboard.dylib", RTLD_NOW);
        _hasInfiniBoard = !!handle;
        handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Infinidock.dylib", RTLD_NOW);
        _hasInfinidock = !!handle;
        handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Cylinder.dylib", RTLD_NOW);
        _hasCylinder = !!handle;
    }
    return self;
}

- (void)addOrUpdateGroupViewForIconView:(SBIconView *)iconView
{
    SBIcon *icon = iconView.icon;
    if (icon == [[CLASS(SBIconController) sharedInstance] grabbedIcon]) {
        return;
    }
    STKGroupView *groupView = [iconView groupView];
    STKPreferences *preferences = [STKPreferences sharedPreferences];
    SBIconCoordinate currentCoordinate = [STKGroupLayoutHandler coordinateForIcon:icon];

    if (!groupView) {
        STKGroup *group = [preferences groupForCentralIcon:icon];
        if (!group) {
            group = [_groupCache objectForKey:icon.leafIdentifier] ?: [self _groupWithEmptySlotsForIcon:icon];
            group.lastKnownCoordinate = currentCoordinate;
            [_groupCache setObject:group forKey:icon.leafIdentifier];
        }
        groupView = [[[STKGroupView alloc] initWithGroup:group iconViewSource:_recycler] autorelease];
        groupView.delegate = self;
        groupView.showPreview = preferences.shouldShowPreviews;
        groupView.showGrabbers = !(preferences.shouldHideGrabbers);
        groupView.activationMode = preferences.activationMode;
        [icon noteBadgeDidChange];
    }
    [groupView.group relayoutForNewCoordinate:currentCoordinate];
    groupView.group.lastKnownCoordinate = currentCoordinate;
}

- (void)removeGroupViewFromIconView:(SBIconView *)iconView
{
    iconView.groupView = nil;
}

- (void)performRotationWithDuration:(NSTimeInterval)duration
{
    STKGroupView *groupView = [STKGroupController sharedController].openGroupView;
    [groupView closeWithCompletionHandler:^{
        [groupView.group forceRelayout];
    }];
    EXECUTE_BLOCK_AFTER_DELAY((duration + 0.01), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingEndedNotificationName object:nil];
    });
}

- (BOOL)handleClosingEvent:(STKClosingEvent)event
{
    BOOL handled = NO;
    if (event == STKClosingEventHomeButtonPress) {
        BOOL sbIsFrontMost = ![(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];
        if (sbIsFrontMost && ([self _activeGroupView] || _selectionView)) {
            handled = [self _closeOpenGroupOrSelectionView];
        }
    }
    else if (!_selectionView) {
        // scroll, switcher open, or lock
        handled = [self _closeOpenGroupOrSelectionView];
    }
    if (handled) {
        CLog(@"Handling closing event: %@", NSStringFromSTKClosingEvent(event));
    }
    return handled;
}

- (void)handleStatusBarTap
{
    if ([STKPreferences sharedPreferences].shouldOpenSpotlightFromStatusBarTap && !_selectionView) {
        [[CLASS(SBSearchGesture) sharedInstance] revealAnimated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (NSEC_PER_SEC * 0.15)), dispatch_get_main_queue(), ^{
            if ([CLASS(SBSearchViewController) instancesRespondToSelector:@selector(_setShowingKeyboard:)]) {
                [[CLASS(SBSearchViewController) sharedInstance] _setShowingKeyboard:YES];
            }
        });
    }
}

- (void)handleIconRemoval:(SBIcon *)removedIcon
{
    if (!removedIcon || [removedIcon isDownloadingIcon]) {
        return;
    }
    SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];
    STKGroup *group = nil;
    if ((group = [[[[STKPreferences sharedPreferences] groupForCentralIcon:removedIcon] retain] autorelease])) {
        if (group.empty) {
            return;
        }
        NSArray *icons = [group.layout allIcons];
        for (SBIcon *icon in icons) {
            STKGroupSlot slot = [group.layout slotForIcon:icon];
            [group removeIconInSlot:slot];
        }
        [group finalizeState];
        [[STKPreferences sharedPreferences] removeGroup:group];
        [model _postIconVisibilityChangedNotificationShowing:icons hiding:nil];
    }
    else if ((group = [[STKPreferences sharedPreferences] groupForSubappIcon:removedIcon])) {
        if (group.empty) {
            return;
        }
        STKGroupSlot slot = [group.layout slotForIcon:removedIcon];
        [group removeIconInSlot:slot];
        [group finalizeState];
        [model _postIconVisibilityChangedNotificationShowing:@[removedIcon] hiding:nil];
    }
}

- (STKGroupView *)activeGroupView
{
    return [self _activeGroupView];
}

- (STKGroup *)_groupWithEmptySlotsForIcon:(SBIcon *)icon
{
    STKGroupLayout *slotLayout = [STKGroupLayoutHandler emptyLayoutForIconAtLocation:[STKGroupLayoutHandler locationForIcon:icon]];
    STKGroup *group = [[STKGroup alloc] initWithCentralIcon:icon layout:slotLayout];
    group.state = STKGroupStateEmpty;
    [group addObserver:[STKPreferences sharedPreferences]];
    return [group autorelease];
}

- (STKGroupView *)_activeGroupView
{
    return (_openGroupView ?: _openingGroupView);
}

- (void)_setAllowScrolling:(BOOL)allow
{
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    [self _currentScrollView].scrollEnabled = allow;
    UIScrollView *scrollView = [[controller currentRootIconList].subviews firstObject];
    if ([scrollView isKindOfClass:CLASS(IFInfiniboardScrollView)]) {
        // Infiniboard
        scrollView.scrollEnabled = allow;
    }
    scrollView = [((UIView *)[[CLASS(SBIconController) sharedInstance] dockListView]).subviews firstObject];
    if ([scrollView isKindOfClass:CLASS(UIScrollView)]) {
        // Infinidock
        scrollView.scrollEnabled = allow;
    }
    SBIconListPageControl *pageControl = [[controller _currentFolderController].contentView valueForKey:@"pageControl"];
    pageControl.userInteractionEnabled = allow;
}

- (UIScrollView *)_currentScrollView
{
    SBFolderController *currentFolderController = [[CLASS(SBIconController) sharedInstance] _currentFolderController];
    return [currentFolderController.contentView scrollView];
}

- (void)_setupDimmingView
{
    if (_hasCylinder) {
        return;
    }
    [self _removeDimmingView];

    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    if ([controller hasOpenFolder]) {
        // Don't add the dimming view
        return;
    }
    SBIconListView *listView = STKCurrentListView();

    // The list dimming view should cover itself, the list view before, and the one after it.
    CGRect frame = [UIScreen mainScreen].bounds;
    frame.origin.x -= frame.size.width;
    frame.origin.y -= 40.f;
    frame.size.width *= 3.f;
    frame.size.height += 40.f;
    _listDimmingView = [[UIView alloc] initWithFrame:frame];

    _listDimmingView.backgroundColor = [UIColor colorWithWhite:0.f alpha:1.f];
    _listDimmingView.alpha = 0.f;
    _listDimmingView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

    [listView addSubview:_listDimmingView];

    STKGroupView *activeGroupView = [self _activeGroupView];
    [activeGroupView.superview.superview bringSubviewToFront:activeGroupView.superview];
}

- (void)_removeDimmingView
{
    if (_listDimmingView) {
        [_listDimmingView removeFromSuperview];
        [_listDimmingView release];
        _listDimmingView = nil;
        [STKCurrentListView() stk_reorderIconViews];
    }
}

- (void)_setDimStrength:(CGFloat)strength
{
    if (_hasCylinder) {
        return;
    }
    if (!_listDimmingView) {
        [self _setupDimmingView];
    }
    _listDimmingView.alpha = strength;
}

- (void)_addCloseGestureRecognizers
{
    UIView *view = [[CLASS(SBIconController) sharedInstance] contentView];
    [view addGestureRecognizer:_closeSwipeRecognizer];
    [view addGestureRecognizer:_closeTapRecognizer];
}

- (void)_removeCloseGestureRecognizers
{
    [_closeTapRecognizer.view removeGestureRecognizer:_closeTapRecognizer];
    [_closeSwipeRecognizer.view removeGestureRecognizer:_closeSwipeRecognizer];
}

- (BOOL)_closeOpenGroupOrSelectionView
{
    BOOL closed = NO;
    if (_selectionView) {
        if (_selectionView.isKeyboardVisible) {
            [_selectionView dismissKeyboard];
        }
        else {
            [self _closeSelectionView];
            closed = YES;
        }
    }
    else if (_openGroupView.group.hasPlaceholders && (_openGroupViewWasModified == NO)) {
        [_openGroupView.group removePlaceholders];
    }
    else if (!_closingGroupView) {
        _closingGroupView = [self _activeGroupView];
        [_closingGroupView close];
        closed = (_closingGroupView != nil);
    }
    return closed;
}

- (void)_showSelectionViewForIconView:(SBIconView *)selectedIconView
{
    // This method can be called before the open animation on the group has finished
    // So, ensure that _openGroupView is not nil
    _openGroupView = [self _activeGroupView];

    _selectionSlot = [_openGroupView.subappLayout slotForIcon:selectedIconView];
    _selectionView = [[[STKSelectionView alloc] initWithFrame:CGRectZero
                                                 selectedIcon:([selectedIconView.icon isLeafIcon] ? selectedIconView.icon : nil)
                                                  centralIcon:_openGroupView.group.centralIcon] autorelease];

    SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];

    NSMutableSet *visibleIconIdentifiers = [[[model visibleIconIdentifiers] mutableCopy] autorelease];
    [visibleIconIdentifiers addObjectsFromArray:[STKPreferences sharedPreferences].identifiersForSubappIcons];
    [visibleIconIdentifiers removeObject:_openGroupView.group.centralIcon.leafIdentifier];

    // User a mutable set to prevent duplicates, if any.
    NSMutableSet *availableIcons = [NSMutableSet setWithCapacity:visibleIconIdentifiers.count];
    for (NSString *identifier in visibleIconIdentifiers) {
        SBIcon *icon = [model expectedIconForDisplayIdentifier:identifier];
        BOOL iconIsWithoutGroup = ![[STKPreferences sharedPreferences] groupForCentralIcon:icon];
        if (icon && iconIsWithoutGroup && ![icon isDownloadingIcon]) {
            [availableIcons addObject:icon];
        }
    }
    _selectionView.iconsForSelection = [availableIcons allObjects];
    _selectionView.selectionHandler = ^{
        if (![selectedIconView.icon isLeafIcon]) {
            [self _closeSelectionView];
        }
    };

    _selectionAnimator = [[STKGroupSelectionAnimator alloc] initWithSelectionView:_selectionView iconView:selectedIconView];
    [_selectionAnimator openSelectionViewAnimatedWithCompletion:nil];
    [self _setAllowScrolling:NO];
}

- (void)_selectIconForCurrentSlot:(SBIcon *)iconToSelect
{
    _openGroupViewWasModified = YES;
    Class emptyReplacementClass = (_openGroupView.group.state == STKGroupStateEmpty ? CLASS(STKEmptyIcon) : CLASS(STKPlaceholderIcon));
    if (!iconToSelect) {
        NSUInteger emptyCount = 0;
        for (SBIcon *icon in _openGroupView.group.layout) {
            if (![icon isLeafIcon]) {
                emptyCount++;
            }
        }
        if (emptyCount >= 3) {
            emptyReplacementClass = CLASS(STKEmptyIcon);
        }
    }
    SBIcon *iconInSelectedSlot = [_openGroupView.group.layout iconInSlot:_selectionSlot];

    if (!_iconsToHide) _iconsToHide = [NSMutableArray new];
    if (!_iconsToShow) _iconsToShow = [NSMutableArray new];

    if ([iconInSelectedSlot isLeafIcon]) {
        // Show the icon that is being replaced
        [_iconsToShow addObject:iconInSelectedSlot];
    }
    if (iconToSelect && (iconToSelect != iconInSelectedSlot)) {
        // The selected icon needs to be hidden from the home screen
        [_iconsToHide addObject:iconToSelect];

        STKGroupSlot slotForIconIfAlreadyInGroup = [_openGroupView.group.layout slotForIcon:iconToSelect];
        if (slotForIconIfAlreadyInGroup.index != NSNotFound) {
            // the group already contains this icon, so replace it with an empty icon
            [_openGroupView.group replaceIconInSlot:slotForIconIfAlreadyInGroup withIcon:[[emptyReplacementClass new] autorelease]];
        }
    }
    else if (!iconToSelect) {
        iconToSelect = [[emptyReplacementClass new] autorelease];
    }
    [_openGroupView.group replaceIconInSlot:_selectionSlot withIcon:iconToSelect];
    if ([iconToSelect isKindOfClass:CLASS(STKPlaceholderIcon)]) {
        [_openGroupView.group.placeholderLayout addIcon:iconToSelect toIconsAtPosition:_selectionSlot.position];
    }
    if (_openGroupView.group.state != STKGroupStateEmpty) {
        [_openGroupView.group addPlaceholders];
    }
}

- (void)_closeSelectionView
{
    [self _selectIconForCurrentSlot:_selectionView.selectedIcon];
    [_selectionAnimator closeSelectionViewAnimatedWithCompletion:^{
        [_selectionView removeFromSuperview];
        [_selectionView release];
        _selectionView = nil;
        [_selectionAnimator release];
        _selectionAnimator = nil;

        [self _setAllowScrolling:YES];
    }];
}

- (void)_prefsChanged
{
    SBIconController *iconController = [CLASS(SBIconController) sharedInstance];
    STKPreferences *preferences = [STKPreferences sharedPreferences];
    NSMutableArray *listViews = [NSMutableArray array];
    if ([iconController dockListView]) [listViews addObject:[iconController dockListView]];
    [listViews addObjectsFromArray:[iconController _rootFolderController].iconListViews];
    if ([iconController _currentFolderController] != [iconController _rootFolderController]) {
        [listViews addObjectsFromArray:[iconController _currentFolderController].iconListViews];
    }
    for (SBIconListView *listView in listViews) {
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView) {
            STKGroupView *groupView = iconView.groupView;
            groupView.activationMode = preferences.activationMode;
            groupView.showGrabbers = !(preferences.shouldHideGrabbers);
            groupView.showPreview = preferences.shouldShowPreviews;
            [iconView.icon noteBadgeDidChange];
        }];
    }
    [[CLASS(SBSearchGesture) sharedInstance] stk_setEnabled:!preferences.shouldDisableSearchGesture];
}

#pragma mark - Group View Delegate
- (BOOL)shouldGroupViewOpen:(STKGroupView *)groupView
{
    BOOL shouldOpen = YES;
    if (([STKPreferences sharedPreferences].activationMode == STKActivationModeNone)
     || ((groupView.group.state == STKGroupStateEmpty) && [STKPreferences sharedPreferences].shouldLockLayouts)) {
        shouldOpen = NO;
    }
    else {
        shouldOpen = (_openGroupView == nil);
    }
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    BOOL presentingShortcutMenu = (([controller respondsToSelector:@selector(presentedShortcutMenu)]) && (controller.presentedShortcutMenu != nil));
    return (shouldOpen && !presentingShortcutMenu);
}

- (BOOL)groupView:(STKGroupView *)groupView shouldRecognizeGesturesSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)recognizer
{
    BOOL allow = YES;
    STKActivationMode activationMode = [STKPreferences sharedPreferences].activationMode;
    if (recognizer == _closeSwipeRecognizer || recognizer == _closeTapRecognizer) {
        allow = NO;
    }
    else if ([recognizer isKindOfClass:[UISwipeGestureRecognizer class]]) {
        UISwipeGestureRecognizerDirection recognizerDirection = [(UISwipeGestureRecognizer *)recognizer direction];
        if ((activationMode & STKActivationModeSwipeUp) && !(activationMode & STKActivationModeSwipeDown)) {
            // Allow all directions other than Up
            allow = !(recognizerDirection & UISwipeGestureRecognizerDirectionUp);
        }
        else if ((activationMode & STKActivationModeSwipeDown) && !(activationMode & STKActivationModeSwipeUp)) {
            // Allow all directions other than Down
            allow = !(recognizerDirection & UISwipeGestureRecognizerDirectionDown);
        }
        else if (STKActivationModeIsUpAndDown(activationMode)) {
            allow = NO;
        }
    }
    else if ([recognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        NSArray *targets = [recognizer valueForKey:@"_targets"];
        id target = [targets firstObject];
        target = [target valueForKey:@"_target"];
        BOOL activationModeConflictsWithSearch = ((activationMode & STKActivationModeSwipeUp) || (activationMode & STKActivationModeSwipeDown));
        allow = (!([target isKindOfClass:CLASS(SBSearchScrollView)] && activationModeConflictsWithSearch)
                && [recognizer.view isKindOfClass:[UIScrollView class]]);
    }
    return allow;
}

- (void)groupViewWillOpen:(STKGroupView *)groupView
{
    _openingGroupView = groupView;
    [self _setAllowScrolling:NO];
    [groupView.group.centralIcon noteBadgeDidChange];
    for (SBIcon *icon in groupView.group.layout) {
        [icon noteBadgeDidChange];
    }
    [self _addCloseGestureRecognizers];
    [[CLASS(SBSearchGesture) sharedInstance] stk_setEnabled:NO];
}

- (void)groupView:(STKGroupView *)groupView didMoveToOffset:(CGFloat)offset
{
    [self _setDimStrength:fminf((offset * kFullDimStrength), kFullDimStrength)];
}

- (void)groupViewDidOpen:(STKGroupView *)groupView
{
    _openingGroupView = nil;
    if (groupView.isOpen) {
        _openGroupView = groupView;
        [self _setAllowScrolling:YES];
    }
}

- (void)groupViewWillClose:(STKGroupView *)groupView
{
    [self _setAllowScrolling:YES];
    _openingGroupView = nil;
    [groupView.group.centralIcon noteBadgeDidChange];
    for (SBIcon *icon in groupView.group.layout) {
        [icon noteBadgeDidChange];
    }
    [[CLASS(SBSearchGesture) sharedInstance] stk_setEnabled:YES];
}

- (void)groupViewDidClose:(STKGroupView *)groupView
{
    if (_openGroupViewWasModified) {
        _openGroupView.group.state = STKGroupStateDirty;
        [_openGroupView.group finalizeState];
        if (_iconsToHide.count > 0 || _iconsToShow.count > 0) {
            SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];
            NSDictionary *userInfo = @{@"SBIconModelIconsToShowKey": _iconsToShow, @"SBIconModelIconsToHideKey": _iconsToHide};
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SBIconModelVisibilityDidChangeNotification" object:model userInfo:userInfo];
            [_iconsToShow release];
            [_iconsToHide release];
            _iconsToShow = nil;
            _iconsToHide = nil;
            [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingEndedNotificationName object:nil];
            [groupView resetLayouts];
        }
    }
    [self _removeDimmingView];
    [self _removeCloseGestureRecognizers];
    _openGroupView = nil;
    _closingGroupView = nil;
    _openGroupViewWasModified = NO;
}

- (void)groupViewWillBeDestroyed:(STKGroupView *)groupView
{
    if (groupView == _openGroupView) {
        [self groupViewDidClose:groupView];
        [[CLASS(SBSearchGesture) sharedInstance] stk_setEnabled:YES];
    }
    else if (groupView == _openingGroupView) {
        _openingGroupView = nil;
    }
}

- (void)iconTapped:(SBIconView *)iconView
{
    STKGroupView *activeGroupView = [self _activeGroupView];
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    if (!activeGroupView) {
        [controller iconTapped:iconView];
        return;
    }
    EXECUTE_BLOCK_AFTER_DELAY(0.2, ^{
        [iconView setHighlighted:NO];
    });
    BOOL presentingShortcutMenu = ([controller respondsToSelector:@selector(presentedShortcutMenu)]) && (controller.presentedShortcutMenu != nil);
    if (presentingShortcutMenu) {
        return;
    }

    if ((iconView.groupView == activeGroupView) && activeGroupView.group.hasPlaceholders) {
        [self _closeOpenGroupOrSelectionView];
        return;
    }
    if (iconView.apexOverlayView) {
        [self _showSelectionViewForIconView:iconView];
    }
    else {
        BOOL protectedByAsphaleia = [(asphaleiaMainClass *)[objc_getClass("asphaleiaMainClass") sharedInstance] possiblyProtectApp:iconView.icon.leafIdentifier inView:iconView];
        if (!protectedByAsphaleia) {
            if ([iconView.icon respondsToSelector:@selector(launchFromLocation:)]) {
                [iconView.icon launchFromLocation:SBIconLocationHomeScreen];
            }
            else if ([iconView.icon respondsToSelector:@selector(launchFromLocation:context:)]) {
                [iconView.icon launchFromLocation:SBIconLocationHomeScreen context:nil];
            }
            if ([STKPreferences sharedPreferences].shouldCloseOnLaunch) {
                [activeGroupView close];
            }
        }
    }
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    if (!_openGroupView) {
        return [controller iconShouldAllowTap:iconView];
    }
    if (_wasLongPressed) {
        _wasLongPressed = NO;
        return NO;
    }
    BOOL presentingShortcutMenu = (([controller respondsToSelector:@selector(presentedShortcutMenu)]) && (controller.presentedShortcutMenu != nil));
    return (!_selectionView && !presentingShortcutMenu);
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    BOOL presentingShortcutMenu = (([controller respondsToSelector:@selector(presentedShortcutMenu)]) && (controller.presentedShortcutMenu != nil));
    if (![self _activeGroupView] || ![iconView.icon isLeafIcon] || presentingShortcutMenu) {
        [[CLASS(SBIconController) sharedInstance] iconHandleLongPress:iconView];
        return;
    }
    _wasLongPressed = YES;
    [iconView setHighlighted:NO];

    STKGroup *group = ([iconView containerGroupView] ?: [iconView groupView]).group;
    if (!group.empty) {
        [group addPlaceholders];
    }
}

// iOS 10
- (void)iconHandleLongPress:(SBIconView *)iconView withFeedbackBehavior:(id)feedbackBehavior {
    [self iconHandleLongPress:iconView];
}

- (void)iconTouchBegan:(SBIconView *)iconView
{
    if (![self _activeGroupView]) {
        [[CLASS(SBIconController) sharedInstance] iconTouchBegan:iconView];
        return;
    }
    [iconView setHighlighted:YES];
    [iconView setNeedsLayout];
}

- (void)icon:(SBIconView *)iconView touchMoved:(UITouch *)touch
{
    if (!_openGroupView) {
        [[CLASS(SBIconController) sharedInstance] icon:iconView touchMoved:touch];
        return;
    }
    if (_wasLongPressed) {
        CGPoint location = [touch locationInView:[iconView _iconImageView]];
        _wasLongPressed = [[iconView _iconImageView] pointInside:location withEvent:nil];
    }
}

- (void)icon:(SBIconView *)iconView touchEnded:(BOOL)ended
{
    if (_openGroupView) {
        // I don't care about this method on open group views.
        return;
    }
    [[CLASS(SBIconController) sharedInstance] icon:iconView touchEnded:ended];
}

#pragma mark - Gesture Recognizer Delegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
    STKGroupView *activeGroupView = [self _activeGroupView];
    BOOL shouldReceiveTouch = NO;
    if (_selectionView) {
        // If a selection view is active, then we only need to ensure that the touch is not on the it.
        BOOL touchIsOutsideSelectionView = !([_selectionView.contentView hitTest:[touch locationInView:_selectionView.contentView]
                                                                       withEvent:nil]);
        shouldReceiveTouch = touchIsOutsideSelectionView;
    }
    else {
        // Since there's not selection view, we can receive the touch as long as it isn't on the active group view
        BOOL touchIsOutsideActiveGroupView = !([activeGroupView hitTest:[touch locationInView:activeGroupView] withEvent:nil]);
        shouldReceiveTouch = touchIsOutsideActiveGroupView;
    }
    return shouldReceiveTouch;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return (otherGestureRecognizer.view == [[[CLASS(SBIconController) sharedInstance] _currentFolderController].contentView scrollView]);
}

#pragma mark - SUPER HAXXX
/*
    Instead of implementing (and forwarding) each method of SBIconViewDelegate to SBIconController, we only implement those which we require.
    We then implement -forwardInvocation and forward the requisite methods to SBIconController.
    However, SBIconView checks (using -respondsToSelector:) whether we implement any given method in SBIconViewDelegate.
    SO, we override -respondsToSelector: too! H4XX
*/
- (BOOL)__selectorIsPartOfIconViewDelegateProtocol:(SEL)selector
{
    Protocol *iconViewDelegateProtocol = @protocol(SBIconViewDelegate);
    struct objc_method_description methodDescription = protocol_getMethodDescription(iconViewDelegateProtocol,
                                                                                     selector,
                                                                                     NO,
                                                                                     YES);
    return (methodDescription.name != NULL && methodDescription.types != NULL);
}

- (BOOL)respondsToSelector:(SEL)selector
{
    if ([self __selectorIsPartOfIconViewDelegateProtocol:selector]) {
        return YES;
    }
    return [super respondsToSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    SEL selector = [invocation selector];
    if ([self __selectorIsPartOfIconViewDelegateProtocol:selector]
     && [[CLASS(SBIconController) sharedInstance] respondsToSelector:selector])  {
        [invocation invokeWithTarget:[CLASS(SBIconController) sharedInstance]];
    }
    else {
        [super forwardInvocation:invocation];
    }
}

@end

