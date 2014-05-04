#import "STKGroupController.h"
#import "STKConstants.h"
#import <dlfcn.h>

#define kFullDimStrength 0.4f

@implementation STKGroupController
{
    STKGroupView *_openGroupView;
    UIView *_listDimmingView;
    UIView *_dockDimmingView;
    UISwipeGestureRecognizer *_closeSwipeRecognizer;
    UITapGestureRecognizer *_closeTapRecognizer;
    
    BOOL _wasLongPressed;

    STKGroupSelectionAnimator *_selectionAnimator;
    STKSelectionView *_selectionView;
    STKGroupSlot _selectionSlot;

    NSMutableArray *_iconsToShow;
    NSMutableArray *_iconsToHide;
    BOOL _openGroupViewWasModified;
    BOOL _hasInfiniBoard;
    BOOL _hasInfinidock;
    BOOL _hasClassicDock;
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_prefsChanged)
                                                     name:(NSString *)STKPrefsChangedNotificationName
                                                   object:nil];
        void *handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Infiniboard.dylib", RTLD_NOW);
        _hasInfiniBoard = !!handle;
        handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Infinidock.dylib", RTLD_NOW);
        _hasInfinidock = !!handle;
        handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/ClassicDock.dylib", RTLD_NOW);
        _hasClassicDock = !!handle;
    }
    return self;
}

- (void)addOrUpdateGroupViewForIconView:(SBIconView *)iconView
{
    if (iconView.icon == [[CLASS(SBIconController) sharedInstance] grabbedIcon]) {
        return;
    }
    STKGroupView *groupView = [iconView groupView];
    STKPreferences *preferences = [STKPreferences sharedPreferences];
    if (!groupView) {
        STKGroup *group = [preferences groupForCentralIcon:iconView.icon];
        if (!group) {
            group = [self _groupWithEmptySlotsForIcon:iconView.icon];
        }
        groupView = [[[STKGroupView alloc] initWithGroup:group] autorelease];
        [iconView setGroupView:groupView];
    }
    groupView.delegate = self;
    groupView.showPreview = preferences.shouldShowPreviews;
    groupView.showGrabbers = !(preferences.shouldHideGrabbers);
    groupView.activationMode = preferences.activationMode;
    [iconView.icon noteBadgeDidChange];

    SBIconCoordinate currentCoordinate = [STKGroupLayoutHandler coordinateForIcon:iconView.icon];
    if (ISPAD()) {
        [groupView.group forceRelayout];
    }
    else {
        [groupView.group relayoutForNewCoordinate:currentCoordinate];
    }
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
        if (![(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication] && (_openGroupView || _selectionView)) {
            handled = YES;
            [self _closeOpenGroupOrSelectionView];
        }
    }
    else if (!_selectionView) {
        // scroll, switcher open, or lock
        handled = ([self _activeGroupView] != nil);
        [self _closeOpenGroupOrSelectionView];
    }
    return handled;
}

- (void)handleIconRemoval:(SBIcon *)removedIcon
{
    STKGroup *group = nil;
    if ((group = [[[[STKPreferences sharedPreferences] groupForCentralIcon:removedIcon] retain] autorelease])) {
        [[STKPreferences sharedPreferences] removeGroup:group];
        SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];
        [model _postIconVisibilityChangedNotificationShowing:[group.layout allIcons] hiding:nil];
    }
    else if ((group = [[STKPreferences sharedPreferences] groupForSubappIcon:removedIcon])) {
        STKGroupSlot slot = [group.layout slotForIcon:removedIcon];
        [group removeIconInSlot:slot];
        [group finalizeState];
    }
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
    [self _currentScrollView].scrollEnabled = allow;
    UIScrollView *scrollView = [[CLASS(SBIconController) sharedInstance] currentRootIconList].subviews[0];
    if ([scrollView isKindOfClass:CLASS(IFInfiniboardScrollView)]) {
        // Infiniboard
        scrollView.scrollEnabled = allow;
    }
    scrollView = [[[CLASS(SBIconController) sharedInstance] dockListView].subviews firstObject];
    if ([scrollView isKindOfClass:CLASS(UIScrollView)]) {
        // Infinidock
        scrollView.scrollEnabled = allow;
    }
}

- (UIScrollView *)_currentScrollView
{
    SBFolderController *currentFolderController = [[CLASS(SBIconController) sharedInstance] _currentFolderController];
    return [currentFolderController.contentView scrollView];
}

- (void)_setupDimmingViews
{
    [self _removeDimmingViews];

    SBIconController *controller = [CLASS(SBIconController) sharedInstance];
    if ([controller hasOpenFolder]) {
        // Don't add the dimming view
        return;
    }

    SBIconListView *listView = STKCurrentListView();
    SBDockIconListView *dock = [controller dockListView];

    // The list dimming view should cover itself, the list view before, and the one after it.
    CGRect frame = [UIScreen mainScreen].bounds;
    frame.origin.x -= frame.size.width;
    frame.origin.y -= dock.frame.size.height;
    frame.size.width *= 3.f;
    frame.size.height += dock.frame.size.height;
    _listDimmingView = [[UIView alloc] initWithFrame:frame];
    _dockDimmingView = (_hasClassicDock ? nil : [[UIView alloc] initWithFrame:dock.bounds]);

    _listDimmingView.backgroundColor = _dockDimmingView.backgroundColor = [UIColor colorWithWhite:0.f alpha:1.f];
    _listDimmingView.alpha = _dockDimmingView.alpha = 0.f;
    _listDimmingView.autoresizingMask = _dockDimmingView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

    [listView addSubview:_listDimmingView];
    [dock addSubview:_dockDimmingView];

    STKGroupView *activeGroupView = [self _activeGroupView];
    [activeGroupView.superview.superview bringSubviewToFront:activeGroupView.superview];
}

- (void)_removeDimmingViews
{
    [_listDimmingView removeFromSuperview];
    [_dockDimmingView removeFromSuperview];
    [_listDimmingView release];
    [_dockDimmingView release];
    _listDimmingView = nil;
    _dockDimmingView = nil;
}

- (void)_setDimStrength:(CGFloat)strength
{
    if (!(_listDimmingView || _dockDimmingView)) {
        // At least one dimming view should be set up.
        [self _setupDimmingViews];
    }

    _listDimmingView.alpha = _dockDimmingView.alpha = strength;
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

- (void)_closeOpenGroupOrSelectionView
{
    if (_selectionView) {
        if (_selectionView.isKeyboardVisible) {
            [_selectionView dismissKeyboard];
        }
        else {
            [self _closeSelectionView];
        }
    }
    else if (_openGroupView.group.hasPlaceholders && (_openGroupViewWasModified == NO)) {
        [_openGroupView.group removePlaceholders];
    }
    else {
        [[self _activeGroupView] close];
    }
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
    
    NSMutableArray *visibleIconIdentifiers = [[[[[model visibleIconIdentifiers] objectEnumerator] allObjects] mutableCopy] autorelease];
    [visibleIconIdentifiers addObjectsFromArray:[STKPreferences sharedPreferences].identifiersForSubappIcons];
    [visibleIconIdentifiers removeObject:_openGroupView.group.centralIcon.leafIdentifier];

    // User a mutable set to prevent duplicates, if any.
    NSMutableSet *availableIcons = [NSMutableSet setWithCapacity:visibleIconIdentifiers.count];
    for (NSString *identifier in visibleIconIdentifiers) {
        SBIcon *icon = [model expectedIconForDisplayIdentifier:identifier];
        BOOL iconIsWithoutGroup = ![[STKPreferences sharedPreferences] groupForCentralIcon:icon];
        if (icon && iconIsWithoutGroup) {
            [availableIcons addObject:icon];
        }
    }

    _selectionView.iconsForSelection = [[availableIcons objectEnumerator] allObjects];
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
    NSMutableArray *listViews = [NSMutableArray arrayWithObject:[iconController dockListView]];
    [listViews addObjectsFromArray:[iconController _rootFolderController].iconListViews];
    if ([iconController _currentFolderController] != [iconController _rootFolderController]) {
        [listViews addObjectsFromArray:[iconController _currentFolderController].iconListViews];
    }
    for (SBIconListView *listView in listViews) {
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView) {
            STKGroupView *groupView = [iconView groupView];
            groupView.activationMode = preferences.activationMode;
            groupView.showGrabbers = !(preferences.shouldHideGrabbers);
            groupView.showPreview = preferences.shouldShowPreviews;
            [iconView.icon noteBadgeDidChange];
        }];
    }
    [[CLASS(SBSearchGesture) sharedInstance] setEnabled:!preferences.shouldDisableSearchGesture];
}

#pragma mark - Group View Delegate
- (BOOL)shouldGroupViewOpen:(STKGroupView *)groupView
{
    BOOL shouldOpen = YES;
    if ((groupView.group.state == STKGroupStateEmpty) && [STKPreferences sharedPreferences].shouldLockLayouts) {
        shouldOpen = NO;
    }
    else {
        shouldOpen = (_openGroupView == nil);
    }
    return shouldOpen;
}

- (BOOL)groupView:(STKGroupView *)groupView shouldRecognizeGesturesSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)recognizer
{
    BOOL allow = YES;
    if ([recognizer isKindOfClass:[UISwipeGestureRecognizer class]] || [recognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        if (recognizer == _closeSwipeRecognizer || recognizer == _closeTapRecognizer) {
            allow = NO;
        }
        else if ([recognizer.delegate isKindOfClass:CLASS(LAIconViewGestureRecognizerDelegate)]
              || [recognizer.delegate isKindOfClass:CLASS(IconToolSwipeHelper)]) {
            allow = YES;
        }
        else {
            NSArray *targets = [recognizer valueForKey:@"_targets"];
            id target = ((targets.count > 0) ? targets[0] : nil);
            target = [target valueForKey:@"_target"];
            STKActivationMode activationMode = [STKPreferences sharedPreferences].activationMode;
            BOOL activationModeConflictsWithSearch = (activationMode != STKActivationModeSwipeUp && activationMode != STKActivationModeDoubleTap);
            allow = (!([target isKindOfClass:CLASS(SBSearchScrollView)] && activationModeConflictsWithSearch)
                    && [recognizer.view isKindOfClass:[UIScrollView class]]);
        }
    }
    return allow;
}

- (void)groupViewWillOpen:(STKGroupView *)groupView
{
    _openingGroupView = groupView;
    if (groupView.activationMode != STKActivationModeDoubleTap) {
        [self _setAllowScrolling:NO];
    }
    [groupView.group.centralIcon noteBadgeDidChange];
    for (SBIcon *icon in groupView.group.layout) {
        [icon noteBadgeDidChange];
    }
    [self _addCloseGestureRecognizers];
    [[CLASS(SBSearchGesture) sharedInstance] setEnabled:NO];
}

- (void)groupView:(STKGroupView *)groupView didMoveToOffset:(CGFloat)offset
{
    [self _setDimStrength:fminf((offset * kFullDimStrength), kFullDimStrength)];
}

- (void)groupViewDidOpen:(STKGroupView *)groupView
{
    _openingGroupView = nil;
    _openGroupView = groupView;
    [self _setAllowScrolling:YES];
}

- (void)groupViewWillClose:(STKGroupView *)groupView
{
    [self _setAllowScrolling:YES];
    _openingGroupView = nil;
    [groupView.group.centralIcon noteBadgeDidChange];
    for (SBIcon *icon in groupView.group.layout) {
        [icon noteBadgeDidChange];
    }
    [[CLASS(SBSearchGesture) sharedInstance] setEnabled:YES];
}

- (void)groupViewDidClose:(STKGroupView *)groupView
{
    if (_openGroupViewWasModified) {
        _openGroupView.group.state = STKGroupStateDirty;
        [_openGroupView.group finalizeState];
        if (_iconsToHide.count > 0 || _iconsToShow.count > 0) {
            SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];
            [model _postIconVisibilityChangedNotificationShowing:_iconsToShow hiding:_iconsToHide];
            [_iconsToShow release];
            [_iconsToHide release];
            _iconsToShow = nil;
            _iconsToHide = nil;
            [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingEndedNotificationName object:nil];
            [groupView resetLayouts];
        }
    }
    [self _removeDimmingViews];
    [self _removeCloseGestureRecognizers];
    _openGroupView = nil;
    _openGroupViewWasModified = NO;
}

- (void)groupViewWillBeDestroyed:(STKGroupView *)groupView
{
    if (groupView == _openGroupView) {
        [self groupViewDidClose:groupView];
        [[CLASS(SBSearchGesture) sharedInstance] setEnabled:YES];
    }
    else if (groupView == _openingGroupView) {
        _openingGroupView = nil;
    }
}

- (void)iconTapped:(SBIconView *)iconView
{
    STKGroupView *activeGroupView = [self _activeGroupView];
    if (!activeGroupView) {
        [[CLASS(SBIconController) sharedInstance] iconTapped:iconView];
        return;
    }
    EXECUTE_BLOCK_AFTER_DELAY(0.2, ^{
        [iconView setHighlighted:NO];
    });
    if ((iconView.groupView == activeGroupView) && activeGroupView.group.hasPlaceholders) {
        [self _closeOpenGroupOrSelectionView];
        return;
    }
    if (iconView.apexOverlayView) {
        [self _showSelectionViewForIconView:iconView];
    }
    else {
        [iconView.icon launchFromLocation:SBIconLocationHomeScreen];
        if ([STKPreferences sharedPreferences].shouldCloseOnLaunch) {
            [activeGroupView close];
        }
    }
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    if (!_openGroupView) {
        return [[CLASS(SBIconController) sharedInstance] iconShouldAllowTap:iconView];
    }
    if (_wasLongPressed) {
        _wasLongPressed = NO;
        return NO;
    }
    return !_selectionView;
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    if (![self _activeGroupView] || ![iconView.icon isLeafIcon]) {
        [[CLASS(SBIconController) sharedInstance] iconHandleLongPress:iconView];
        return;
    }
    _wasLongPressed = YES;
    [iconView setHighlighted:NO];
    [([iconView containerGroupView] ?: [iconView groupView]).group addPlaceholders];
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
