#import "STKGroupController.h"
#import "STKConstants.h"
#import <dlfcn.h>

#define kFullDimStrength 0.2f

@implementation STKGroupController
{
    STKGroupView *_openGroupView;
    UIView *_dimmingView;
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
        void *handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Infiniboard.dylib", RTLD_LAZY);
        _hasInfiniBoard = !!handle;
        dlclose(handle);
        handle = dlopen("/Library/MobileSubstrate/DynamicLibraries/Infinidock.dylib", RTLD_LAZY);
        _hasInfinidock = !!handle;
        dlclose(handle);
    }
    return self;
}

- (void)addGroupViewToIconView:(SBIconView *)iconView
{
    if (iconView.icon == [[CLASS(SBIconController) sharedInstance] grabbedIcon]) {
        return;
    }
    STKGroupView *groupView = nil;
    if ((groupView = [iconView groupView])) {
        SBIconCoordinate currentCoordinate = [STKGroupLayoutHandler coordinateForIcon:iconView.icon];
        if (ISPAD()) {
            [groupView.group forceRelayout];
        }
        else {
            [groupView.group relayoutForNewCoordinate:currentCoordinate];
        }
    }
    else {
        STKGroup *group = [[STKPreferences sharedPreferences] groupForCentralIcon:iconView.icon];
        if (!group) {
            group = [self _groupWithEmptySlotsForIcon:iconView.icon];
        }
        group.lastKnownCoordinate = [STKGroupLayoutHandler coordinateForIcon:group.centralIcon];
        groupView = [[[STKGroupView alloc] initWithGroup:group] autorelease];
        [iconView setGroupView:groupView];
    }
    groupView.delegate = self;
    groupView.showPreview = [STKPreferences sharedPreferences].shouldShowPreviews;
    groupView.showGrabbers = !([STKPreferences sharedPreferences].shouldHideGrabbers);
    groupView.activationMode = [STKPreferences sharedPreferences].activationMode;
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
        // scroll event 
        handled = (_openGroupView != nil);
        [self _closeOpenGroupOrSelectionView];
    }
    return handled;
}

- (STKGroup *)_groupWithEmptySlotsForIcon:(SBIcon *)icon
{
    STKGroupLayout *slotLayout = [STKGroupLayoutHandler emptyLayoutForIconAtLocation:[STKGroupLayoutHandler locationForIcon:icon]];
    STKGroup *group = [[STKGroup alloc] initWithCentralIcon:icon layout:slotLayout];
    group.state = STKGroupStateEmpty;
    [group addObserver:[STKPreferences sharedPreferences]];
    return [group autorelease];
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

- (void)_setDimStrength:(CGFloat)strength
{
    if (!_dimmingView) {
        SBWallpaperController *controller = [CLASS(SBWallpaperController) sharedInstance];
        UIView *homescreenWallpaperView = [controller valueForKey:@"_homescreenWallpaperView"] ?: [controller valueForKey:@"_sharedWallpaperView"];
        // if the same wallpaper is used for the home as well as lock screen, _homescreenWallpaperView is nil
        _dimmingView = [[UIView alloc] initWithFrame:homescreenWallpaperView.bounds];
        _dimmingView.backgroundColor = [UIColor colorWithWhite:0.f alpha:1.f];
        _dimmingView.alpha = 0.f;
        _dimmingView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        [homescreenWallpaperView addSubview:_dimmingView];
    }
    _dimmingView.alpha = strength;
}

- (void)_removeDimmingView
{
    [_dimmingView removeFromSuperview];
    [_dimmingView release];
    _dimmingView = nil;
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
    STKGroup *openGroup = _openGroupView.group;
    if (_selectionView) {
        [self _closeSelectionView];
    }
    else if ([openGroup hasPlaceholders]) {
        if ([openGroup.layout allIcons].count == [openGroup.placeholderLayout allIcons].count) {
            [_openGroupView close];
        }
        else {
            [openGroup removePlaceholders];
        }
    }
    else {
        [_openGroupView close];
    }
}

- (void)_showSelectionViewForIconView:(SBIconView *)selectedIconView
{
    _selectionSlot = [_openGroupView.subappLayout slotForIcon:selectedIconView];
    _selectionView = [[[STKSelectionView alloc] initWithFrame:CGRectZero
                                                 selectedIcon:([selectedIconView.icon isLeafIcon] ? selectedIconView.icon : nil)
                                                  centralIcon:_openGroupView.group.centralIcon] autorelease];
    
    SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];
    NSMutableArray *visibleIconIdentifiers = [[[[[model visibleIconIdentifiers] objectEnumerator] allObjects] mutableCopy] autorelease];
    [visibleIconIdentifiers addObjectsFromArray:[STKPreferences sharedPreferences].identifiersForSubappIcons];
    NSMutableArray *availableIcons = [NSMutableArray array];
    for (NSString *identifier in visibleIconIdentifiers) {
        SBIcon *icon = [model expectedIconForDisplayIdentifier:identifier];
        if (![[STKPreferences sharedPreferences] groupForCentralIcon:icon]) {
            [availableIcons addObject:icon];
        }
    }
    _selectionView.iconsForSelection = availableIcons;
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
        // The icon that is being replaced
        [_iconsToShow addObject:iconInSelectedSlot];
    }
    if (iconToSelect && iconToSelect != iconInSelectedSlot) {
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
    NSMutableArray *listViews = [NSMutableArray array];
    [listViews addObjectsFromArray:[iconController _rootFolderController].iconListViews];
    [listViews addObject:[iconController dockListView]];
    for (SBIconListView *listView in listViews) {
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView) {
            [iconView groupView].showPreview = [STKPreferences sharedPreferences].shouldShowPreviews;
            [iconView groupView].activationMode = [STKPreferences sharedPreferences].activationMode;
            [iconView groupView].showGrabbers = !([STKPreferences sharedPreferences].shouldHideGrabbers);
            [iconView.icon noteBadgeDidChange];
        }];
    }
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
    if (groupView.activationMode != STKActivationModeDoubleTap) {
        [self _setAllowScrolling:NO];
    }
    _openGroupView = groupView;
    [groupView.group.centralIcon noteBadgeDidChange];
}

- (void)groupView:(STKGroupView *)groupView didMoveToOffset:(CGFloat)offset
{
    [self _setDimStrength:MIN((offset * kFullDimStrength), kFullDimStrength)];
}

- (void)groupViewDidOpen:(STKGroupView *)groupView
{
    [self _addCloseGestureRecognizers];
    [[CLASS(SBSearchGesture) sharedInstance] setEnabled:NO];
    [self _setAllowScrolling:YES];
}

- (void)groupViewWillClose:(STKGroupView *)groupView
{
    [self _setAllowScrolling:YES];
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
    [self _removeDimmingView];
    [self _removeCloseGestureRecognizers];
    [[CLASS(SBSearchGesture) sharedInstance] setEnabled:YES];
    _openGroupView = nil;
    _openGroupViewWasModified = NO;
    [groupView.group.centralIcon noteBadgeDidChange];
}

- (void)groupViewWillBeDestroyed:(STKGroupView *)groupView
{
    if (groupView == _openGroupView) {
        _openGroupView = nil;
    }
}

- (void)iconTapped:(SBIconView *)iconView
{
    if (!self.openGroupView) {
        [[CLASS(SBIconController) sharedInstance] iconTapped:iconView];
        return;
    }
    EXECUTE_BLOCK_AFTER_DELAY(0.2, ^{
        [iconView setHighlighted:NO];
    });
    if (iconView.apexOverlayView) {
        [self _showSelectionViewForIconView:iconView];
    }
    else {
        [iconView.icon launchFromLocation:SBIconLocationHomeScreen];
        if ([STKPreferences sharedPreferences].shouldCloseOnLaunch) {
            [self.openGroupView close];
        }
    }
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    if (!self.openGroupView) {
        return [[CLASS(SBIconController) sharedInstance] iconShouldAllowTap:iconView];
    }
    if (_wasLongPressed) {
        _wasLongPressed = NO;
        return NO;
    }
    return !_selectionView;
}

- (BOOL)iconViewDisplaysCloseBox:(SBIconView *)iconView
{
    if ([iconView groupView]) {
        return [[CLASS(SBIconController) sharedInstance] iconViewDisplaysCloseBox:iconView];
    }
    return NO;
}

- (void)iconCloseBoxTapped:(SBIconView *)iconView
{
    [[CLASS(SBIconController) sharedInstance] iconCloseBoxTapped:iconView];
}

- (void)icon:(SBIconView *)iconView openFolder:(SBFolder *)folder animated:(BOOL)animated
{
    [[CLASS(SBIconController) sharedInstance] icon:iconView openFolder:folder animated:animated];
}

- (BOOL)iconViewDisplaysBadges:(SBIconView *)iconView
{
    return [[CLASS(SBIconController) sharedInstance] iconViewDisplaysBadges:iconView];
}

- (BOOL)icon:(SBIconView *)iconView canReceiveGrabbedIcon:(SBIconView *)grabbedIconView
{
    STKGroup *grabbedGroup = [grabbedIconView groupView].group;
    STKGroup *group = [iconView groupView].group;
    
    return (group.state == STKGroupStateEmpty && grabbedGroup.state == STKGroupStateEmpty);
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    if (!self.openGroupView || ![iconView.icon isLeafIcon]) {
        [[CLASS(SBIconController) sharedInstance] iconHandleLongPress:iconView];
        return;
    }
    _wasLongPressed = YES;
    [iconView setHighlighted:NO];

    [([iconView containerGroupView] ?: [iconView groupView]).group addPlaceholders];
}

- (void)iconTouchBegan:(SBIconView *)iconView
{
    if (!self.openGroupView) {
        [[CLASS(SBIconController) sharedInstance] iconTouchBegan:iconView];
        return;
    }
    [iconView setHighlighted:YES];   
}

- (void)icon:(SBIconView *)iconView touchMoved:(UITouch *)touch
{
    if (!self.openGroupView) {
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
    if (self.openGroupView) {
        // Nobody cares
        return;
    }
    [[CLASS(SBIconController) sharedInstance] icon:iconView touchEnded:ended];
}

- (CGFloat)iconLabelWidth
{
    return [[CLASS(SBIconController) sharedInstance] iconLabelWidth];
}

#pragma mark - Gesture Recognizer Delegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
    CGPoint point = [touch locationInView:_openGroupView];
    if (_selectionView) {
        return (CGRectContainsPoint(_selectionView.contentView.frame, [touch locationInView:_selectionView]) == false);
    }
    return !([_openGroupView hitTest:point withEvent:nil]);
}

@end
