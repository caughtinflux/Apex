#import "STKGroupController.h"
#import "STKConstants.h"

@implementation STKGroupController
{
    STKGroupView *_openGroupView;
    UISwipeGestureRecognizer *_closeSwipeRecognizer;
    UITapGestureRecognizer *_closeTapRecognizer;
    SBScaleIconZoomAnimator *_zoomAnimator;
    STKSelectionView *_selectionView;
    BOOL _openGroupIsEditing;
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
        STKGroup *group = [[STKPreferences preferences] groupForIcon:iconView.icon];
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
    return [group autorelease];
}

- (UIScrollView *)_currentScrollView
{
    SBFolderController *currentFolderController = [[CLASS(SBIconController) sharedInstance] _currentFolderController];
    return [currentFolderController.contentView scrollView];
}

- (void)_closeOpenGroupView
{
    if (_selectionView) {
        [UIView animateWithDuration:0.25f animations:^{
            _selectionView.alpha = 0.f;
        }];
        [_zoomAnimator animateToFraction:0.f afterDelay:0 withCompletion:^{
            [_selectionView removeFromSuperview];
            [_selectionView release];
            _selectionView = nil;
        }];
    }
    else {
        [_openGroupView close];
        [self _removeCloseGestureRecognizers];
    }
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

#pragma mark - Group View Delegate
- (BOOL)shouldGroupViewOpen:(STKGroupView *)groupView
{
    return !_openGroupView;
}

- (BOOL)groupView:(STKGroupView *)groupView shouldRecognizeGesturesSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)recognizer
{
    if (recognizer == _closeSwipeRecognizer || recognizer == _closeTapRecognizer) {
        return NO;
    }
    NSArray *targets = [recognizer valueForKey:@"_targets"];
    id target = ((targets.count > 0) ? targets[0] : nil);
    target = [target valueForKey:@"_target"];
    return (![target isKindOfClass:CLASS(SBSearchScrollView)] && [recognizer.view isKindOfClass:[UIScrollView class]]);
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
    if (_openGroupIsEditing) {
        for (SBIconView *iconView in _openGroupView.subappLayout) {
            [iconView removeApexOverlay];
        }
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
    if (_openGroupIsEditing) {
        return;
    }
    EXECUTE_BLOCK_AFTER_DELAY(0.2, ^{
        [iconView setHighlighted:NO];
    });
    if ([iconView.icon isEmptyPlaceholder]) {
        SBIcon *icon = iconView.icon;
        SBRootFolderController *rfc = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _rootFolderController];
        _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:rfc targetIcon:icon];
        SBScaleZoomSettings *settings = [[[CLASS(SBScaleZoomSettings) alloc] init] autorelease];
        [settings setDefaultValues];
        _zoomAnimator.settings = settings;
        [_zoomAnimator prepare];

        [_zoomAnimator animateToFraction:1.0 afterDelay:0.0 withCompletion:^{
            SBIconContentView *cv = [(SBIconController *)[CLASS(SBIconController) sharedInstance] contentView];
            _selectionView = [[[STKSelectionView alloc] initWithFrame:CGRectZero delegate:self] autorelease];
            _selectionView.center = (CGPoint){(CGRectGetWidth(cv.frame) * 0.5f), (CGRectGetHeight(cv.frame) * 0.5f)};
            _selectionView.delegate = self;
            [UIView animateWithDuration:0.25 animations:^{
                CGRect endFrame = (CGRect){{0.f, 0.f}, [CLASS(SBFolderBackgroundView) folderBackgroundSize]};
                _selectionView.frame = endFrame;
                _selectionView.center = (CGPoint){(CGRectGetWidth(cv.frame) * 0.5f), (CGRectGetHeight(cv.frame) * 0.5f)};
            }];
            NSSet *icons = [[(SBIconController *)[CLASS(SBIconController) sharedInstance] model] leafIcons];
            NSMutableArray *availableIcons = [NSMutableArray array];
            for (SBIcon *icon in icons) {
                if ([[(SBIconController *)[CLASS(SBIconController) sharedInstance] model] isIconVisible:icon]) {
                    [availableIcons addObject:icon];
                }
            }
            _selectionView.iconsForSelection = availableIcons;
            [cv addSubview:_selectionView];
        }];
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
    if ([iconView.icon isEmptyPlaceholder] || _openGroupView == nil) {
        return;
    }
    [iconView setHighlighted:NO];
    for (SBIconView *iconView in _openGroupView.subappLayout) {
        [iconView showApexOverlayOfType:STKOverlayTypeEditing];
    }
    _openGroupIsEditing = YES;
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
    
}

@end
