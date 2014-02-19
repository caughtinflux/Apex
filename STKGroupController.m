#import "STKGroupController.h"
#import "STKConstants.h"

@implementation STKGroupController
{
    STKGroupView *_openGroupView;
    UISwipeGestureRecognizer *_closeSwipeRecognizer;
    UITapGestureRecognizer *_closeTapRecognizer;
    SBScaleIconZoomAnimator *_zoomAnimator;
    STKSelectionView *_selectionView;
    STKGroupSlot _selectionSlot;
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
        _closeTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_closeOpenGroupView)];
        _closeSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(_closeOpenGroupView)];
        _closeSwipeRecognizer.direction = (UISwipeGestureRecognizerDirectionUp | UISwipeGestureRecognizerDirectionDown);
        _closeSwipeRecognizer.delegate = self;
        _closeTapRecognizer.delegate = self;
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
        [groupView.group relayoutForNewCoordinate:currentCoordinate];
    }
    else {
        STKGroup *group = [[STKPreferences sharedPreferences] groupForIcon:iconView.icon];
        if (!group) {
            group = [self _groupWithEmptySlotsForIcon:iconView.icon];
        }
        group.lastKnownCoordinate = [STKGroupLayoutHandler coordinateForIcon:group.centralIcon];
        groupView = [[[STKGroupView alloc] initWithGroup:group] autorelease];
        groupView.delegate = self;
        [iconView setGroupView:groupView];
    }
}

- (void)removeGroupViewFromIconView:(SBIconView *)iconView
{
    iconView.groupView = nil;
}

- (STKGroup *)_groupWithEmptySlotsForIcon:(SBIcon *)icon
{
    STKGroupLayout *slotLayout = [STKGroupLayoutHandler emptyLayoutForIconAtLocation:[STKGroupLayoutHandler locationForIcon:icon]];
    STKGroup *group = [[STKGroup alloc] initWithCentralIcon:icon layout:slotLayout];
    group.state = STKGroupStateEmpty;
    [group addObserver:[STKPreferences sharedPreferences]];
    return [group autorelease];
}

- (UIScrollView *)_currentScrollView
{
    SBFolderController *currentFolderController = [[CLASS(SBIconController) sharedInstance] _currentFolderController];
    return [currentFolderController.contentView scrollView];
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

- (void)_closeOpenGroupView
{
    if (_selectionView) {
        [self _closeSelectionView];
    }
    else if ([_openGroupView.group hasPlaceholders]) {
        [_openGroupView.group removePlaceholders];
    }
    else {
        [_openGroupView close];
    }
}

- (void)_showSelectionViewForIconView:(SBIconView *)selectedIconView
{
    _selectionSlot = [_openGroupView.subappLayout slotForIcon:selectedIconView];

    SBRootFolderController *rfc = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _rootFolderController];
    SBScaleZoomSettings *settings = [[[CLASS(SBScaleZoomSettings) alloc] init] autorelease];
    [settings setDefaultValues];

    SBIconContentView *cv = [(SBIconController *)[CLASS(SBIconController) sharedInstance] contentView];
    _selectionView = [[[STKSelectionView alloc] initWithFrame:CGRectZero delegate:self] autorelease];
    _selectionView.center = (CGPoint){(CGRectGetWidth(cv.frame) * 0.5f), (CGRectGetHeight(cv.frame) * 0.5f)};
    _selectionView.delegate = self;
    SBIconModel *model = [(SBIconController *)[CLASS(SBIconController) sharedInstance] model];
    NSSet *icons = [model leafIcons];
    NSMutableArray *availableIcons = [NSMutableArray array];
    for (SBIcon *icon in icons) {
        if (icon != selectedIconView.icon && [model isIconVisible:icon]) {
            [availableIcons addObject:icon];
        }
    }
    _selectionView.iconsForSelection = availableIcons;
    _selectionView.alpha = 0.0f;
    [cv addSubview:_selectionView];

    _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:rfc targetIcon:selectedIconView.icon];    
    _zoomAnimator.settings = settings;
    [_zoomAnimator prepare];

    CGSize size = [CLASS(SBFolderBackgroundView) folderBackgroundSize];
    CGPoint center = _selectionView.center;
    CGPoint origin = (CGPoint){(center.x - (size.width * 0.5)), (center.y - (size.width * 0.5))};
    [UIView animateWithDuration:0.25 animations:^{
        _selectionView.frame = (CGRect){origin, size};
        _selectionView.alpha = 1.f;
    }];
    [_zoomAnimator animateToFraction:1.0 afterDelay:0.0 withCompletion:nil];
}

- (void)_closeSelectionView
{
    [UIView animateWithDuration:0.25f animations:^{
        _selectionView.alpha = 0.f;
    }];
    [_zoomAnimator animateToFraction:0.f afterDelay:0 withCompletion:^{
        [_selectionView removeFromSuperview];
        [_selectionView release];
        _selectionView = nil;
    }];
}

#pragma mark - Group View Delegate
- (BOOL)shouldGroupViewOpen:(STKGroupView *)groupView
{
    return !_openGroupView;
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
            allow = (![target isKindOfClass:CLASS(SBSearchScrollView)] && [recognizer.view isKindOfClass:[UIScrollView class]]);
        }
    }
    return allow;
}

- (void)groupViewWillOpen:(STKGroupView *)groupView
{
    if (groupView.activationMode != STKActivationModeDoubleTap) {
        [self _currentScrollView].scrollEnabled = NO;
    }
}

- (void)groupViewDidOpen:(STKGroupView *)groupView
{
    _openGroupView = groupView;
    [self _addCloseGestureRecognizers];
    [[CLASS(SBSearchGesture) sharedInstance] setEnabled:NO];
    [self _currentScrollView].scrollEnabled = YES;
}

- (void)groupViewWillClose:(STKGroupView *)groupView
{
    [self _currentScrollView].scrollEnabled = YES;
}

- (void)groupViewDidClose:(STKGroupView *)groupView
{
    if (_openGroupView.group.state == STKGroupStateDirty) {
        [_openGroupView.group finalizeState];
        [_openGroupView resetLayouts];
    }
    [self _removeCloseGestureRecognizers];
    [[CLASS(SBSearchGesture) sharedInstance] setEnabled:YES];
    _openGroupView = nil;
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return YES;   
}

- (void)groupViewWillBeDestroyed:(STKGroupView *)groupView
{
    if (groupView == _openGroupView){
        _openGroupView = nil;
    }
}

- (void)iconTapped:(SBIconView *)iconView
{
    EXECUTE_BLOCK_AFTER_DELAY(0.2, ^{
        [iconView setHighlighted:NO];
    });
    if (iconView.apexOverlayView) {
        [self _showSelectionViewForIconView:iconView];
    }
    else {
        [iconView.icon launchFromLocation:SBIconLocationHomeScreen];        
    }
}

- (BOOL)iconViewDisplaysCloseBox:(SBIconView *)iconView
{
    return NO;
}

- (BOOL)iconViewDisplaysBadges:(SBIconView *)iconView
{
    return [[CLASS(SBIconController) sharedInstance] iconViewDisplaysBadges:iconView];
}

- (BOOL)icon:(SBIconView *)iconView canReceiveGrabbedIcon:(SBIcon *)grabbedIcon
{
    return NO;
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    if ([iconView.icon isEmptyPlaceholder] || [iconView.icon isPlaceholder]) {
        return;
    }
    [iconView setHighlighted:NO];
    [[iconView containerGroupView].group addPlaceholders]; 
}

- (void)iconTouchBegan:(SBIconView *)iconView
{
    [iconView setHighlighted:YES];   
}

- (void)icon:(SBIconView *)iconView touchEnded:(BOOL)ended
{
    [iconView setHighlighted:NO];
}

#pragma mark - Gesture Recognizer Delegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
    CGPoint point = [touch locationInView:_openGroupView];
    return !([_openGroupView hitTest:point withEvent:nil]);   
}

#pragma mark - Icon Selection
- (void)selectionView:(STKSelectionView *)selectionView didSelectIconView:(SBIconView *)iconView
{
    [_openGroupView.group replaceIconInSlot:_selectionSlot withIcon:iconView.icon];
    [_openGroupView.group addPlaceholders];
    [self _closeSelectionView];
}

@end
