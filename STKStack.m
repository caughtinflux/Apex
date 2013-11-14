#import "STKStack+Private.h"
#import "STKIconLayoutHandler.h"
#import "STKSelectionView.h"    

#import "SBIconListView+ApexAdditions.h"
#import "SBIconViewMap+STKSafety.h"
#import "NSOperationQueue+STKMainQueueDispatch.h"
#import "STKPlaceholderIcon.h"

#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

/*
*   Compatibility imports
*/
#import "IWWidgetsView.h"

@implementation STKStack
{
    SBIcon                   *_centralIcon;
    STKIconLayout            *_appearingIconLayout;
    STKIconLayout            *_displacedIconLayout;
    NSMutableSet             *_hiddenIcons;
    STKIconLayout            *_iconViewLayout;

    CGRect                   _topGrabberOriginalFrame;
    CGRect                   _bottomGrabberOriginalFrame;

    NSOperationQueue         *_closingAnimationOpQueue;
    NSOperationQueue         *_postCloseOpQueue;

    STKIconCoordinates        _iconCoordinates;

    CGFloat                   _distanceRatio;
    CGFloat                   _lastDistanceFromCenter;

    BOOL                      _longPressed; 
    BOOL                      _needsLayout;
    BOOL                      _layoutDiffersFromFile;
    BOOL                      _hasPlaceholders;
    BOOL                      _isClosingSelectionView;

    UISwipeGestureRecognizer *_swipeRecognizer;
    UITapGestureRecognizer   *_tapRecognizer;

    id<SBIconViewDelegate>    _previousDelegate;

    STKSelectionView         *_currentSelectionView;
    STKIconLayout            *_iconsHiddenForPlaceholders;

    STKLayoutPosition         _selectionViewPosition;
    NSUInteger                _selectionViewIndex;

    SBIconController         *_iconController;
}

@synthesize currentIconDistance = _lastDistanceFromCenter;

#pragma mark - Public Methods
- (instancetype)initWithContentsOfFile:(NSString *)file
{
    _iconController = [objc_getClass("SBIconController") sharedInstance];
    SBIconModel *model = [(SBIconController *)_iconController model];

    NSDictionary *attributes = [NSDictionary dictionaryWithContentsOfFile:file];
    NSDictionary *customLayout = attributes[STKStackManagerCustomLayoutKey];
    SBIcon *centralIcon = [model expectedIconForDisplayIdentifier:attributes[STKStackManagerCentralIconKey]];

    if (!STKListViewForIcon(centralIcon)) {
        return nil;
    }

    if (customLayout) {
        return [self initWithCentralIcon:centralIcon withCustomLayout:customLayout];
    }

    NSMutableArray *stackIcons = [NSMutableArray arrayWithCapacity:(((NSArray *)attributes[STKStackManagerStackIconsKey]).count)];
    for (NSString *identifier in attributes[STKStackManagerStackIconsKey]) {
        // Get the SBIcon instances for the identifiers
        SBIcon *icon = [model expectedIconForDisplayIdentifier:identifier];
        if (icon) {
            [stackIcons addObject:[model expectedIconForDisplayIdentifier:identifier]];
        }
        else {
            _layoutDiffersFromFile = YES;
            STKLog(@"Couldn't get icon for identifier %@. Confirm that the ID is correct and the app is installed.", identifier);
        }
    }

    if (!centralIcon) {
        STKLog(@"Central Icon: %@ doesn't exist, dying quietly...", attributes[STKStackManagerCentralIconKey]);
        return nil;
    }

    return [self initWithCentralIcon:centralIcon stackIcons:stackIcons];
}

- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons
{
    if ((self = [super init])) {
        if (!_iconController) {
            _iconController = [objc_getClass("SBIconController") sharedInstance];
        }
        [icons retain];
        _centralIcon = [centralIcon retain];
        if (!STKListViewForIcon(_centralIcon)) {
            return nil;
        }
        STKPositionMask mask = [self _locationMaskForIcon:_centralIcon];
        if (!icons || icons.count == 0) {
            _needsLayout = YES;
            _isEmpty = YES;
        }
        else {
            _appearingIconLayout = [[STKIconLayoutHandler layoutForIcons:icons aroundIconAtPosition:mask] retain];
        }
        [icons release];
        [self _setup];
    }
    
    return self;
}

- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon withCustomLayout:(NSDictionary *)customLayout
{
    STKIconLayout *layout = [STKIconLayout layoutWithDictionary:customLayout];
    if ([layout allIcons].count == 0) {
        return [self initWithCentralIcon:centralIcon stackIcons:nil];
    }
    if (!STKListViewForIcon(centralIcon)) {
        return nil;
    }
    STKIconCoordinates currentCoords = [STKIconLayoutHandler coordinatesForIcon:centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    STKIconCoordinates savedCoords;

    savedCoords.xPos = (customLayout[@"xPos"] ? [customLayout[@"xPos"] integerValue] : NSNotFound);
    savedCoords.yPos = (customLayout[@"yPos"] ? [customLayout[@"yPos"] integerValue] : NSNotFound - 2);
    if (!(EQ_COORDS(savedCoords, currentCoords))) {
        // The location of the icon has changed, hence calculate layouts accordingly
        if ((self = [self initWithCentralIcon:centralIcon stackIcons:[layout allIcons]])) {
            [self _setLayoutDiffersFromFile:YES];
        };
    }
    else if ((self = [super init])) {
        _centralIcon = [centralIcon retain];
        _appearingIconLayout = [layout retain];
        [self _setup];
    }

    return self;
}

- (void)_setLayoutDiffersFromFile:(BOOL)diff
{
    _layoutDiffersFromFile = diff;
}

- (void)_setup
{
    if (!_isEmpty) {
        _displacedIconLayout = [[STKIconLayoutHandler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconLayout] retain];
    }
    _iconCoordinates = [STKIconLayoutHandler coordinatesForIcon:_centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];

    _postCloseOpQueue = [[NSOperationQueue alloc] init];
    [_postCloseOpQueue setSuspended:YES];
    [_postCloseOpQueue setMaxConcurrentOperationCount:1];

    _closingAnimationOpQueue = [[NSOperationQueue alloc] init];
    [_closingAnimationOpQueue setSuspended:YES];
    [_closingAnimationOpQueue setMaxConcurrentOperationCount:1];

    _iconController = [objc_getClass("SBIconController") sharedInstance];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_relayoutRequested:) name:STKRecalculateLayoutsNotification object:nil];
}

- (void)dealloc
{
    [self cleanupView];

    if (_isExpanded) {
        SBIconListView *listView = STKListViewForIcon(_centralIcon);
        [listView setIconsNeedLayout];
        [listView layoutIconsIfNeeded:kAnimationDuration domino:NO];

        [self _setGhostlyAlphaForAllIcons:1.f excludingCentralIcon:NO];
    }

    [self _iconViewForIcon:_centralIcon].delegate = [objc_getClass("SBIconController") sharedInstance];

    [_centralIcon release];
    [_appearingIconLayout release];
    [_displacedIconLayout release];
    [_hiddenIcons release];

    [_postCloseOpQueue cancelAllOperations];
    [_postCloseOpQueue release];

    [_closingAnimationOpQueue cancelAllOperations];
    [_closingAnimationOpQueue release];

    [_topGrabberView release];
    [_bottomGrabberView release];

    [self _cleanupGestureRecognizers];

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super dealloc];
}

- (id)init
{
    NSAssert(NO, @"**** You MUST use -[STKStackManager initWithCentralIcon:stackIcons:]");
    return nil;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p; centralIcon = %@; stackIcons = %zd>", [self class], self, _centralIcon, [_appearingIconLayout allIcons].count];
}

- (void)recalculateLayouts
{
    NSArray *stackIcons = [_appearingIconLayout allIcons];

    STKIconCoordinates current = [STKIconLayoutHandler coordinatesForIcon:_centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];

    [_displacedIconLayout release];

    STKPositionMask mask = [self _locationMaskForIcon:_centralIcon];
    STKIconLayout *suggestedLayout = nil;

    if (_isEmpty || [_appearingIconLayout allIcons].count == 0) {
        _isEmpty = YES;
        [_appearingIconLayout release];
        _appearingIconLayout = [[STKIconLayoutHandler emptyLayoutForIconAtPosition:mask] retain];
    }
    else if (!(EQ_COORDS(current, _iconCoordinates)) && ([STKIconLayoutHandler layout:_appearingIconLayout requiresRelayoutForPosition:mask suggestedLayout:&suggestedLayout])) {
        [_appearingIconLayout release];
        if (!suggestedLayout) {
            _appearingIconLayout = [[STKIconLayoutHandler layoutForIcons:stackIcons aroundIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
        }
        else {
            _appearingIconLayout = [suggestedLayout retain];
        }
        
        [self.delegate stackDidChangeLayout:self];
    }
    else if (EQ_COORDS(current, _iconCoordinates) == NO) {
        // The coords have changed, but a re-layout isn't necessary
        _iconCoordinates = current;
        [self.delegate stackDidChangeLayout:self];
    }

    _displacedIconLayout = [[self _iconViewForIcon:_centralIcon] isInDock] ? nil : [[STKIconLayoutHandler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconLayout] retain];
    _iconCoordinates = [STKIconLayoutHandler coordinatesForIcon:_centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];

    if (_hasSetup) {
        [self cleanupView];
        [self setupPreview];
    }
}

- (void)removeIconFromAppearingIcons:(SBIcon *)icon
{
    [_appearingIconLayout removeIcon:icon];
    [self recalculateLayouts];
}

#pragma mark - Adding Stack Icons
- (void)setupViewIfNecessary
{
    if (!_hasSetup) {
        [self setupView];
    }
}

- (void)setupView
{
    if (_iconViewLayout) {
        [[_iconViewLayout allIcons] makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [_iconViewLayout removeAllIcons];
        [_iconViewLayout release];
        _iconViewLayout = nil;
    }

    _iconViewLayout = [[STKIconLayout alloc] init];
    
    SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
    centralIconView.userInteractionEnabled = YES;

    [_appearingIconLayout enumerateIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
        SBIconView *iconView = [[[objc_getClass("SBIconView") alloc] initWithDefaultSize] autorelease];
        iconView.location = (SBIconViewLocation)1337;
        [iconView setIcon:icon];
        [iconView setDelegate:self];
        
        iconView.frame = centralIconView.bounds;

        [self _setAlpha:0.f forLabelAndShadowOfIconView:iconView];
        if (!_isEmpty && _showsPreview) {
            iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);
        }
        [_iconViewLayout addIcon:iconView toIconsAtPosition:position];
        if ([centralIconView isGhostly]) {
            iconView.alpha = 0.f;
        }
        [centralIconView insertSubview:iconView atIndex:0];
        iconView.userInteractionEnabled = NO;
        for (UIGestureRecognizer *recognizer in iconView.gestureRecognizers) {
            [iconView removeGestureRecognizer:recognizer];
        }
    }];
    [centralIconView bringSubviewToFront:centralIconView.iconImageView];
    [self _calculateDistanceRatio];

    _hasSetup = YES;
}

- (void)cleanupView
{
    if (!_isEditing) {
        self.isEditing = NO;
    }
    for (SBIconView *iconView in _iconViewLayout) {
        iconView.delegate = nil;
        [iconView removeFromSuperview];
    }
    [_iconViewLayout removeAllIcons];
    [_iconViewLayout release];
    _iconViewLayout = nil;

    _hasSetup = NO;
}

#pragma mark - Preview Handling
- (void)setupPreview
{
    [self setupViewIfNecessary];

    [_iconViewLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
        CGRect frame = [self _iconViewForIcon:_centralIcon].bounds;
        CGPoint newOrigin = frame.origin;
        // Check if it's the last object, only if not empty
        if (!_isEmpty && _showsPreview && idx == currentArray.count - 1) {
            if (![[self _iconViewForIcon:_centralIcon] isGhostly]) {
                iconView.alpha = 1.f;
            }
            // This is probably how the rest of the code should've been written
            CGFloat *memberToModify = (STKLayoutPositionIsVertical(position) ? &newOrigin.y : &newOrigin.x);
            // the member to modify needs to be subtracted from in case of t/l.
            CGFloat negator = (position == STKLayoutPositionTop || position == STKLayoutPositionLeft ? -1 : 1);
            *memberToModify += kPopoutDistance * negator;
        }
        else {
            // Only the last icon at a particular side needs to be shown
            iconView.alpha = 0.f;
        }

        frame.origin = newOrigin; 
        iconView.frame = frame;

        if (!_isEmpty && _showsPreview) {
            // Scale the icon back down to the smaller size
            iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);
        }
        // Hide the labels and shadows
        [self _setAlpha:0.f forLabelAndShadowOfIconView:iconView];
        iconView.userInteractionEnabled = NO;
    }];
}

- (void)touchesBegan
{
    if (_needsLayout) {
        [self recalculateLayouts];
        _needsLayout = NO;
    }
    if (!_hasSetup) {
        [self setupPreview];
    }
    [_iconController prepareToGhostCurrentPageIconsForRequester:kGhostlyRequesterID skipIcon:_centralIcon];
    [self _findIconsToHide];
}

- (void)touchesDraggedForDistance:(CGFloat)distance
{
    if (_isExpanded || [[_iconController scrollView] isDragging]) {
        return;
    }
    BOOL hasVerticalIcons = ([_appearingIconLayout iconsForPosition:STKLayoutPositionTop].count > 0) || ([_appearingIconLayout iconsForPosition:STKLayoutPositionBottom].count > 0);    
    CGFloat alpha = STKAlphaFromDistance(_lastDistanceFromCenter, (hasVerticalIcons ? STKGetCurrentTargetDistance() : STKGetCurrentTargetDistance() * _distanceRatio));
    [self _setGhostlyAlphaForAllIcons:alpha excludingCentralIcon:YES];
    [_iconController setPageControlAlpha:alpha];

    CGFloat midWayDistance = STKGetCurrentTargetDistance() / 2.0;
    [self _moveAllIconsInRespectiveDirectionsByDistance:distance performingTask:^(SBIconView *iv, STKLayoutPosition pos, NSUInteger idx) {
        if (idx == 0) {
            if (hasVerticalIcons && STKLayoutPositionIsVertical(pos)) {
                _lastDistanceFromCenter = floorf(fabsf(iv.frame.origin.y - [self _iconViewForIcon:_centralIcon].bounds.origin.y));
            }
            else if (!hasVerticalIcons && STKLayoutPositionIsHorizontal(pos)) {
               _lastDistanceFromCenter = floorf(fabsf(iv.frame.origin.x - [self _iconViewForIcon:_centralIcon].bounds.origin.x));
            }
        }
        if (!_isEmpty) {
            if (iv.alpha <= 0.f) {
                iv.alpha = 1.f;
            }
            [self _setAlpha:(1 - alpha) forLabelAndShadowOfIconView:iv];

            if (_showsPreview) {       
                if (_lastDistanceFromCenter <= midWayDistance) {
                    // If the icons are past the halfway mark, start increasing/decreasing their scale.
                    // This looks beautiful. Yay me.
                    CGFloat stackIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kStackPreviewIconScale);
                    iv.iconImageView.transform = CGAffineTransformMakeScale(stackIconTransformScale, stackIconTransformScale);
                    
                
                    CGFloat centralIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kCentralIconPreviewScale);
                    [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(centralIconTransformScale, centralIconTransformScale);
                }
                else {      
                    [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
                    iv.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
                }

                [iv _updateAccessoryPosition];
            }
        }
        else {
            iv.alpha = (1 - alpha);
        }
    }];
    
    if (!_showsPreview) {
        CGFloat grabberAlpha = STKScaleNumber(_lastDistanceFromCenter, 0, midWayDistance + 10, 1.0, 0.0);
        distance *= 1.1f; // Make the grabbers go slightly faster than the icon view
        if (_topGrabberView) {
            if (((_topGrabberView.frame.origin.y - distance) < _topGrabberOriginalFrame.origin.y) && _iconViewLayout.topIcons.count > 0) {
                _topGrabberView.frame = (CGRect){{_topGrabberView.frame.origin.x, _topGrabberView.frame.origin.y - distance}, _topGrabberView.frame.size};
            }
            
            _topGrabberView.alpha = grabberAlpha;
            
        }
        if (_bottomGrabberView) {
            if (((_bottomGrabberView.frame.origin.y + distance) > _bottomGrabberOriginalFrame.origin.y) && _iconViewLayout.bottomIcons.count > 0) {
                _bottomGrabberView.frame = (CGRect){{_bottomGrabberView.frame.origin.x, _bottomGrabberView.frame.origin.y + distance}, _bottomGrabberView.frame.size};
            }
         
            _bottomGrabberView.alpha = grabberAlpha;
        }
    }
}

- (void)touchesEnded:(void(^)(void))animationCompletion
{
    if (_lastDistanceFromCenter >= kEnablingThreshold && !_isExpanded) {
        // Set this now, not waiting for the animation to complete, so anyone asking questions gets the right answer... LOL
        _isExpanded = YES;
        [self open];
    }
    else {
        [self closeWithCompletionHandler:animationCompletion];
    }
}
 
- (void)closeWithCompletionHandler:(void(^)(void))completionHandler
{
    [self _animateToClosedPositionWithCompletionBlock:^{
        if (completionHandler) {
            completionHandler();
        }
    } duration:kAnimationDuration animateCentralIcon:YES];
}

- (void)closeForSwitcherWithCompletionHandler:(void(^)(void))completionHandler;
{
    [self _animateToClosedPositionWithCompletionBlock:completionHandler duration:kAnimationDuration animateCentralIcon:YES];
}

- (void)open
{
    [self _animateToOpenPositionWithDuration:kAnimationDuration];
}

- (void)close
{
    [self closeWithCompletionHandler:nil];
}

- (BOOL)handleHomeButtonPress
{
    BOOL didIntercept = NO;
    if (_currentSelectionView) {
        [self hideSelectionView];
        didIntercept = YES;
    }
    else if (_isEditing) {
        self.isEditing = NO;
        didIntercept = YES;
    }
    return didIntercept;
}

#pragma mark - Setter/Getter Overrides
- (void)setIsEditing:(BOOL)editing
{
    if (_isEmpty) {
        return;
    }
    if (editing) {
        [self _insertPlaceholders];
        [self _addOverlays];
    }
    else {
        [self hideSelectionView];
        [self _removePlaceholders];
        [self _removeOverlays];
    }
    _isEditing = editing;
}

- (void)setIconAlpha:(CGFloat)alpha
{
    for (SBIconView *iv in _iconViewLayout) {
        iv.alpha = alpha;
    }
    _topGrabberView.alpha = alpha;
    _bottomGrabberView.alpha = alpha;
}

- (void)setShowsPreview:(BOOL)showsPrev
{
    if (showsPrev == _showsPreview) {
        return;
    }
    _showsPreview = showsPrev;
    if (_showsPreview && !_isEmpty) {
        [self setupPreview];
    }
    if (!_showsPreview && !_isExpanded) {
        [self cleanupView];
    }
}

- (void)setTopGrabberView:(UIView *)view
{
    [_topGrabberView release];
    _topGrabberView = [view retain];
    _topGrabberOriginalFrame = view.frame;
}

- (void)setBottomGrabberView:(UIView *)view
{
    [_bottomGrabberView release];
    _bottomGrabberView = [view retain];
    _bottomGrabberOriginalFrame = view.frame;
}

- (BOOL)isSelecting
{
    return (_currentSelectionView != nil);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////        HAXX        //////////////////////////////////////////////////////////

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    CGRect centralIconViewFrame = [self _iconViewForIcon:_centralIcon].bounds;
    if (CGRectContainsPoint(centralIconViewFrame, point)) {
        return [self _iconViewForIcon:_centralIcon];
    } 
    for (SBIconView *iconView in _iconViewLayout) {
        if (CGRectContainsPoint(iconView.frame, point)) {
            return iconView;
        }
    }
    return nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#pragma mark - Open Animation
- (void)_animateToOpenPositionWithDuration:(NSTimeInterval)duration;
{
    if (!_hasSetup) {
        [self setupPreview];
    }

    [_iconController prepareToGhostCurrentPageIconsForRequester:kGhostlyRequesterID skipIcon:_centralIcon];

    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);

        [_iconViewLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
            CGRect newFrame = iconView.frame;
            
            newFrame.origin = [self _targetOriginForIconAtPosition:position distanceFromCentre:idx + 1];
            iconView.frame = newFrame;
            iconView.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
            
            iconView.delegate = self;
            iconView.userInteractionEnabled = YES;

            iconView.alpha = 1.f;

            if (!iconView.icon.isPlaceholder) {
                [self _setAlpha:1.f forLabelAndShadowOfIconView:iconView];
            }
        }];

        [_displacedIconLayout enumerateIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
            SBIconView *iconView = [self _iconViewForIcon:icon];
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _displacedOriginForIcon:icon withPosition:position];
            iconView.frame = newFrame;
        }];

        [_iconController setPageControlAlpha:0];
        [self _setGhostlyAlphaForAllIcons:0.f excludingCentralIcon:YES];
        for (SBIcon *icon in _hiddenIcons) { [self _iconViewForIcon:icon].alpha = 0.f; }

        _topGrabberView.alpha = 0.f;
        _bottomGrabberView.alpha = 0.f;

        // iWidgets Compat
        IWWidgetsView *widgetsView = [objc_getClass("IWWidgetsView") sharedInstance];
        if (widgetsView) {
            // POS SWAG.
            widgetsView.alpha = 0.f;
        }

        [self _setupGestureRecognizers];
        
    } completion:^(BOOL finished) {
        if (finished) {
            SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
            _previousDelegate = centralIconView.delegate;
            centralIconView.delegate = self;
            centralIconView.userInteractionEnabled = YES;

            _isExpanded = YES;
        }
    }];
}

#pragma mark - Close Animation
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock duration:(NSTimeInterval)duration animateCentralIcon:(BOOL)animateCentralIcon
{
    if (_currentSelectionView) {
        return;
    }

    UIView *centralView = [[self _iconViewForIcon:_centralIcon] iconImageView];
    CGFloat scale = (_isEmpty || !_showsPreview ? 1.f : kCentralIconPreviewScale);

    if (animateCentralIcon && !_isEmpty) {
        [UIView animateWithDuration:(duration * 0.6) delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            // Animate central imageview shrink/grow
            centralView.transform = CGAffineTransformMakeScale(scale - 0.1f, scale - 0.1f);
        } completion:^(BOOL finished) {
            if (finished) {
                // Animate it back to `scale`
                [UIView animateWithDuration:(duration * 0.6) delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    centralView.transform = CGAffineTransformMakeScale(scale, scale);
                } completion:nil];
            }
        }];
    }
    if (_isEmpty || (!animateCentralIcon && !_showsPreview)) {
        centralView.transform = CGAffineTransformMakeScale(scale, scale);
    }
    self.isEditing = NO;
    [self _removePlaceholders];
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        [self setupPreview];

        // Set the alphas back to original
        [self _setGhostlyAlphaForAllIcons:0.999f excludingCentralIcon:NO];
        [_iconController setPageControlAlpha:1];

        // Bring the off screen icons back to life! :D
        for (SBIcon *icon in _hiddenIcons) {
            [self _iconViewForIcon:icon].alpha = 1.f;
        }

        [_closingAnimationOpQueue setSuspended:NO];
        [_closingAnimationOpQueue waitUntilAllOperationsAreFinished];
        [_closingAnimationOpQueue setSuspended:YES];

        if (!animateCentralIcon) {
            centralView.transform = CGAffineTransformMakeScale(scale, scale);
        }

        if (_showsPreview) {
            return;
        }

        _topGrabberView.alpha = 1.f;
        _bottomGrabberView.alpha = 1.f;

        _topGrabberView.frame = _topGrabberOriginalFrame;
        _bottomGrabberView.frame = _bottomGrabberOriginalFrame;

        // iWidgets Compat
        IWWidgetsView *widgetsView = [objc_getClass("IWWidgetsView") sharedInstance];
        if (widgetsView) {
            // POS SWAG.
            widgetsView.alpha = 1.f;
        }
    } completion:^(BOOL finished) {
        if (finished) {
            // Remove the icon view's delegates
            for (SBIconView *iconView in _iconViewLayout) {
                iconView.delegate = nil;
            }
            // XXX: BUGFIX for SBIconListView BS
            [self _setGhostlyAlphaForAllIcons:.9999999f excludingCentralIcon:NO]; // .999f is necessary, unfortunately. A weird 1.0->0.0->1.0 alpha flash happens otherwise
            [self _setGhostlyAlphaForAllIcons:1.f excludingCentralIcon:NO]; // Set it back to 1.f, fix a pain in the ass bug
            [_iconController cleanUpGhostlyIconsForRequester:kGhostlyRequesterID];

            [_hiddenIcons release];
            _hiddenIcons = nil;

            if (_isEmpty || !_showsPreview) {
                // We can remove the place holder icon views if the stack is empty. No need to have 4 icon views hidden behind every damn icon.
                [self cleanupView];
                
                [_hiddenIcons release];
                _hiddenIcons = nil;
                
                if (_isEmpty) {
                    [_appearingIconLayout removeAllIcons];
                    [_appearingIconLayout release];
                    _appearingIconLayout = nil;    
                }
                
                [_displacedIconLayout removeAllIcons];
                [_displacedIconLayout release];
                _displacedIconLayout = nil;

                _needsLayout = YES;
            }
            _isExpanded = NO;
            [_postCloseOpQueue setSuspended:NO];
            [_postCloseOpQueue waitUntilAllOperationsAreFinished];
            [_postCloseOpQueue setSuspended:YES];

            if (completionBlock) {
                completionBlock();
            }
        }
    }];

    if (_previousDelegate) {
        [self _iconViewForIcon:_centralIcon].delegate = _previousDelegate;
        _previousDelegate = nil;
    }
    // Move all icons to their respective locations
    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    [listView setIconsNeedLayout];
    [listView layoutIconsIfNeeded:duration domino:NO];
    _lastDistanceFromCenter = 0.f;
    // Remove recognizers if they're still around
    [self _cleanupGestureRecognizers];
}

#pragma mark - Move ALL the things
// These macros give us information about _a relative to _b, relative to their paths.
#define IS_GREATER(_float_a, _float_b, _position) ((_position == STKLayoutPositionTop || _position == STKLayoutPositionLeft) ? (_float_a < _float_b) : (_float_a > _float_b))
#define IS_LESSER(_float_a, _float_b, _position) ((_position == STKLayoutPositionTop || _position == STKLayoutPositionLeft) ? (_float_a > _float_b) : (_float_a < _float_b))

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance performingTask:(void(^)(SBIconView *iv, STKLayoutPosition pos, NSUInteger idx))task
{
    SBIconListView *listView = STKListViewForIcon(_centralIcon);

    [_displacedIconLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconView *iconView = [self _iconViewForIcon:icon]; // Get the on-screen icon view from the list view.
        CGRect iconFrame = iconView.frame;
        CGRect newFrame = iconView.frame;
        CGPoint originalOrigin = [listView originForIcon:icon];
        CGPoint targetOrigin = [self _displacedOriginForIcon:icon withPosition:position]; 
        NSUInteger appearingIconsCount = [_appearingIconLayout iconsForPosition:position].count;
        CGFloat factoredDistance = (distance * appearingIconsCount);  // Factor the distance up by the number of icons that are coming in at that position
        CGFloat horizontalFactoredDistance = factoredDistance * _distanceRatio; // The distance to be moved horizontally is slightly different than vertical, multiply it by the ratio to have them work perfectly. :)
        CGFloat *targetCoord, *currentCoord, *newCoord, *originalCoord;
        CGFloat moveDistance;

        if (STKLayoutPositionIsVertical(position)) {
            targetCoord = &(targetOrigin.y); 
            currentCoord = &(iconFrame.origin.y);
            newCoord = &(newFrame.origin.y);
            originalCoord = &(originalOrigin.y);
            moveDistance = factoredDistance;
        }
        else {
            targetCoord = &(targetOrigin.x);
            currentCoord = &(iconFrame.origin.x);
            newCoord = &(newFrame.origin.x);
            originalCoord = &(originalOrigin.x);
            moveDistance = horizontalFactoredDistance;
        }
        CGFloat negator = ((position == STKLayoutPositionTop || position == STKLayoutPositionLeft) ? -1.f : 1.f);
        moveDistance *= negator;
        if (IS_GREATER((*currentCoord + (moveDistance / appearingIconsCount)), *targetCoord, position)) {
            // If, after moving, the icon would pass its target, factor the distance back to it's original, for now it has to move only as much as all the other icons
            moveDistance /= appearingIconsCount;
        }
        *targetCoord += kBandingAllowance * negator;
        if (IS_GREATER(*currentCoord + moveDistance, *targetCoord, position)) {
            // Do not go beyong target
            *newCoord = *targetCoord;
        }
        else if (IS_LESSER(*currentCoord + moveDistance, *originalCoord, position)) {
            // Or beyond the original position on the homescreen
            *newCoord = *originalCoord;
        }
        else {
            // Move that shit
            *newCoord += moveDistance;
        }
        iconView.frame = newFrame;
    }];
     
    // Move stack icons
    [_iconViewLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
        if (task) {
            task(iconView, position, idx);
        }
        CGRect iconFrame = iconView.frame;
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _targetOriginForIconAtPosition:position distanceFromCentre:idx + 1];
        CGRect centralFrame = [self _iconViewForIcon:_centralIcon].bounds;
        CGFloat negator = ((position == STKLayoutPositionTop || position == STKLayoutPositionLeft) ? -1.f : 1.f);
        CGFloat distanceRatio = 1.f;
        CGFloat *targetCoord, *currentCoord, *newCoord, *centralCoord;
        CGFloat moveDistance = distance * negator;
        if (STKLayoutPositionIsVertical(position)) {
            targetCoord = &(targetOrigin.y);
            currentCoord = &(iconFrame.origin.y);
            newCoord = &(newFrame.origin.y);
            centralCoord = &(centralFrame.origin.y);
        }
        else {
            targetCoord = &(targetOrigin.x);
            currentCoord = &(iconFrame.origin.x);
            newCoord = &(newFrame.origin.x);
            centralCoord = &(centralFrame.origin.x);
            distanceRatio = _distanceRatio;
        }
        CGFloat multFactor = (IS_LESSER((*currentCoord + moveDistance), *targetCoord, position) ? (idx + 1) : 1);
        CGFloat popComp = (((idx == currentArray.count - 1) && !(_isEmpty || !_showsPreview)) ? ((*targetCoord - kPopoutDistance * negator) / *targetCoord) : 1.f);
        moveDistance *= (distanceRatio * multFactor * popComp);

        if (IS_GREATER((*currentCoord + (moveDistance / popComp)), *targetCoord, position)) {
            // Don't compensate for anything if the icon is moving past the target
            moveDistance /= popComp;
        }
        // Modify the target to allow for a `kBandingAllowance` distance extra for the rubber banding effect
        *targetCoord += (kBandingAllowance * negator);

        if (IS_LESSER((*currentCoord + moveDistance), *centralCoord, position)) {
            newFrame = centralFrame;
        }
        else if (IS_LESSER((*currentCoord + moveDistance), *targetCoord, position)) {
            *newCoord += moveDistance;
        }
        else if (IS_GREATER((*currentCoord + moveDistance), *targetCoord, position)) {
            *newCoord = *targetCoord;
        }
        iconView.frame = newFrame;
    }];
}

#pragma mark - Gesture Recogniser Handling
- (void)_setupGestureRecognizers
{
    // Add gesture recognizers...
    // Store references to them in ivars, so as to get rid of them when a gesture is recognized
    _swipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(_handleCloseGesture:)];
    _swipeRecognizer.direction = (UISwipeGestureRecognizerDirectionUp | UISwipeGestureRecognizerDirectionDown);
    _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleCloseGesture:)];
    _tapRecognizer.numberOfTapsRequired = 1;
    _tapRecognizer.delegate = self;

    UIView *view = nil;
    if (HAS_FE) {
        CLog(@"Has FE");
        view = [self _iconViewForIcon:_centralIcon].superview.superview.superview;
    }
    else {
        view = [[objc_getClass("SBUIController") sharedInstance] contentView];
    }
    [view addGestureRecognizer:_swipeRecognizer];
    [view addGestureRecognizer:_tapRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other
{
    return (other == _currentSelectionView.listTableView.panGestureRecognizer);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
    if (recognizer == _tapRecognizer) {
        // The tap recogniser shouldn't receive a touch if it's on a stacked icon
        SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
        if ([centralIconView pointInside:[touch locationInView:centralIconView] withEvent:nil]) {
            return NO;
        }
        for (SBIconView *iconView in _iconViewLayout) {
            if ([iconView pointInside:[touch locationInView:iconView] withEvent:nil]) {
                return NO;
            }
        }
    }
    return YES;
}

- (void)_handleCloseGesture:(UIGestureRecognizer *)sender
{
    if (_currentSelectionView) {
        return;
    }
    if (self.isEditing && [sender isKindOfClass:[UITapGestureRecognizer class]]) {
        self.isEditing = NO;
        return;
    }
    [self _cleanupGestureRecognizers];
    [self closeWithCompletionHandler:^{ 
        if ([self.delegate respondsToSelector:@selector(stackClosedByGesture:)]) {
            [self.delegate stackClosedByGesture:self];
        }
    }];
}

- (void)_cleanupGestureRecognizers
{
    [_swipeRecognizer.view removeGestureRecognizer:_swipeRecognizer];
    _swipeRecognizer.delegate = nil;
    [_swipeRecognizer release];
    [_tapRecognizer.view removeGestureRecognizer:_tapRecognizer];
    _tapRecognizer.delegate = nil;
    [_tapRecognizer release];
    _swipeRecognizer = nil;
    _tapRecognizer = nil;
}

#pragma mark - Helper Methods
- (SBIconView *)_iconViewForIcon:(SBIcon *)icon
{
    return [[objc_getClass("SBIconViewMap") homescreenMap] safeIconViewForIcon:icon];
}

- (STKPositionMask)_locationMaskForIcon:(SBIcon *)icon
{
    STKPositionMask mask = 0x0;
    if (!icon) {
        return mask;
    }
    if ([[self _iconViewForIcon:icon] isInDock]) {
        return (mask | STKPositionDock);
    }
    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    STKIconCoordinates coordinates = [STKIconLayoutHandler coordinatesForIcon:icon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    if (coordinates.xPos == 0) {
        mask |= STKPositionTouchingLeft;
    }
    if (coordinates.xPos == ([listView iconColumnsForCurrentOrientation] - 1)) {
        mask |= STKPositionTouchingRight;
    }
    if (coordinates.yPos == 0) {
        mask |= STKPositionTouchingTop;
    }
    if (coordinates.yPos == ([listView iconRowsForCurrentOrientation] - 1)) {
        mask |= STKPositionTouchingBottom;
    }
    return mask;
}

- (void)_relayoutRequested:(NSNotification *)notif
{
    if (_isEmpty == NO) {
        [self recalculateLayouts];
        [self setupPreview];
    }
    else {
        _needsLayout = YES;
    }
}

- (CGPoint)_targetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance
{
    // Calculate the positions manually, as -[SBIconListView originForIconAtX:Y:] only gives coordinates that will be on screen, but allow for off-screen icons too.
    SBIconListView *listView = [_iconController currentRootIconList];
    CGRect originalFrame = (CGRect){CGPointZero, [objc_getClass("SBIconView") defaultIconSize]};    
    CGPoint returnPoint = originalFrame.origin;
    NSInteger multiplicationFactor = distance;
    CGFloat pageControlComp = [[self _iconViewForIcon:_centralIcon] isInDock] ? ([_iconController dock].frame.origin.y - 5) : 0.f;
    switch (position) {
        case STKLayoutPositionTop: {
            returnPoint.y = (originalFrame.origin.y - ((originalFrame.size.height + [listView stk_realVerticalIconPadding]) * multiplicationFactor)) - pageControlComp;
            break;
        }
        case STKLayoutPositionBottom: {
            returnPoint.y = originalFrame.origin.y + ((originalFrame.size.height + [listView stk_realVerticalIconPadding]) * multiplicationFactor);    
            break;
        }
        case STKLayoutPositionLeft: {
            returnPoint.x = originalFrame.origin.x - ((originalFrame.size.width + [listView horizontalIconPadding]) * multiplicationFactor);
            break;
        }
        case STKLayoutPositionRight: {
            returnPoint.x = originalFrame.origin.x + ((originalFrame.size.width + [listView horizontalIconPadding]) * multiplicationFactor);
            break;
        }
        default: {
            break;
        }
    }
    return returnPoint;
}

- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position usingLayout:(STKIconLayout *)layout
{
    // Calculate the positions manually, as -[SBIconListView originForIconAtX:Y:] only gives coordinates that will be on screen, but allow for off-screen icons too.
    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    SBIconView *iconView = [self _iconViewForIcon:icon];
    
    CGPoint originalOrigin = [listView originForIcon:icon]; // Use the original location as a reference, as the iconview might have been displaced.
    CGRect originalFrame = (CGRect){originalOrigin, {iconView.frame.size.width, iconView.frame.size.height}};
    CGPoint returnPoint = originalOrigin;
    NSInteger multiplicationFactor = [layout iconsForPosition:position].count;
    switch (position) {
        case STKLayoutPositionTop: {
            returnPoint.y = originalFrame.origin.y - ((originalFrame.size.height + [listView stk_realVerticalIconPadding]) * multiplicationFactor);
            break;
        }
        case STKLayoutPositionBottom: {
            returnPoint.y = originalFrame.origin.y + ((originalFrame.size.height + [listView stk_realVerticalIconPadding]) * multiplicationFactor);    
            break;
        }
        case STKLayoutPositionLeft: {
            returnPoint.x = originalFrame.origin.x - ((originalFrame.size.width + [listView horizontalIconPadding]) * multiplicationFactor);
            break;
        }
        case STKLayoutPositionRight: {
            returnPoint.x = originalFrame.origin.x + ((originalFrame.size.width + [listView horizontalIconPadding]) * multiplicationFactor);
            break;
        }
        default: {
            returnPoint = CGPointZero;
            break;
        }
    }
    
    return returnPoint;
}

- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position
{
    return [self _displacedOriginForIcon:icon withPosition:position usingLayout:_appearingIconLayout];
}

- (void)_calculateDistanceRatio
{
    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    CGPoint referencePoint = [listView originForIconAtX:2 Y:2];
    CGPoint verticalOrigin = [listView originForIconAtX:2 Y:1];
    CGPoint horizontalOrigin = [listView originForIconAtX:1 Y:2];

    CGFloat verticalDistance = referencePoint.y - verticalOrigin.y;
    CGFloat horizontalDistance = referencePoint.x - horizontalOrigin.x;

    _distanceRatio = (horizontalDistance / verticalDistance);
}

- (void)_findIconsToHide
{
    [_hiddenIcons release];
    _hiddenIcons = nil;
    _hiddenIcons = [NSMutableSet new];
    SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
    if (![centralIconView isInDock]) {
        CGRect listViewBounds = STKListViewForIcon(_centralIcon).bounds;
        [_displacedIconLayout enumerateIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
            CGPoint target = [self _displacedOriginForIcon:icon withPosition:position];
            CGRect targetRect = (CGRect){{target.x, target.y}, [self _iconViewForIcon:icon].frame.size};
            switch (position) {
                case STKLayoutPositionTop: {
                    if (CGRectGetMaxY(targetRect) <= (listViewBounds.origin.y + 20)) {
                        // Add 20 to account for status bar frame
                        [_hiddenIcons addObject:icon];
                    }
                    break;
                }
                case STKLayoutPositionBottom: {
                    if (target.y + 10 > listViewBounds.size.height) {
                        [_hiddenIcons addObject:icon];
                    }
                    break;
                }
                case STKLayoutPositionLeft: {
                    if (CGRectGetMaxX(targetRect) <= listViewBounds.origin.y) {
                        [_hiddenIcons addObject:icon];
                    }
                    break;
                }
                case STKLayoutPositionRight: {
                    if (CGRectGetMinX(targetRect) >= CGRectGetWidth(listViewBounds)) {
                        [_hiddenIcons addObject:icon];
                    }
                    break;
                }
                default: {
                    break;
                }
            }
        }];
    }
    else {
        [_iconViewLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
            CGPoint targetOrigin = [self _targetOriginForIconAtPosition:position distanceFromCentre:idx + 1];
            CGRect targetFrame = (CGRect){targetOrigin, iconView.frame.size};
            targetFrame = [iconView.superview convertRect:targetFrame toView:[_iconController currentRootIconList]];
            [[_iconController currentRootIconList] makeIconViewsPerformBlock:^(SBIconView *mainListViewIconView) {
                if (CGRectIntersectsRect(targetFrame, mainListViewIconView.frame)) {
                    [_hiddenIcons addObject:mainListViewIconView.icon];
                }
            }];
        }];
    }
}

#pragma mark - Alpha Shit

- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral
{
    if (HAS_FE) {
        for (SBIcon *icon in _hiddenIcons) {
            [self _iconViewForIcon:icon].alpha = alpha;
        }
        alpha = STKScaleNumber(alpha, 1.0, 0.0, 1.0, 0.2);
        [STKListViewForIcon(_centralIcon) makeIconViewsPerformBlock:^(SBIconView *iconView) {
            if (excludeCentral && iconView.icon == _centralIcon) {
                return;
            }
            iconView.alpha = alpha;
            if (alpha <= 0.99) {
                iconView.userInteractionEnabled = NO;
            }
            else {
                iconView.userInteractionEnabled = YES;
            }
        }];
    }
    else {
        for (SBIcon *icon in _hiddenIcons) {
            [self _iconViewForIcon:icon].alpha = alpha;
        }
    }
    if (alpha >= 1.f) {
        [_iconController setCurrentPageIconsGhostly:NO forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];
    }
    else if (alpha <= 0.f) {
        [_iconController setCurrentPageIconsGhostly:YES forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];   
    }
    else {
        [_iconController setCurrentPageIconsPartialGhostly:alpha forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];
    }
}

- (void)_setAlpha:(CGFloat)alpha forLabelAndShadowOfIconView:(SBIconView *)iconView
{
    ((UIImageView *)[iconView valueForKey:@"_shadow"]).alpha = alpha;
    [iconView setIconLabelAlpha:alpha];
    ((UIView *)[iconView valueForKey:@"_accessoryView"]).alpha = alpha;
}

#pragma mark - Editing Handling
- (void)_addOverlays
{
    for (SBIconView *iconView in _iconViewLayout) {
        if (iconView.icon.isPlaceholder) {
            continue;
        }

        [self _addOverlayOnIconView:iconView];
    }
}

- (void)_addOverlayOnIconView:(SBIconView *)iconView
{
    UIImageView *imageView = objc_getAssociatedObject(iconView, @selector(overlayView));
    if (!imageView) {
        imageView = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:PATH_TO_IMAGE(@"EditingOverlay")]];
        imageView.center = iconView.iconImageView.center;

        [UIView animateWithDuration:kOverlayDuration animations:^{
            imageView.alpha = 0.f;
            [iconView addSubview:imageView];
            imageView.alpha = 1.f;
        }];

        objc_setAssociatedObject(iconView, @selector(overlayView), imageView, OBJC_ASSOCIATION_ASSIGN);
    }
}

- (void)_removeOverlays
{
    MAP([_iconViewLayout allIcons], ^(SBIconView *iconView) {
        UIImageView *overlayView = objc_getAssociatedObject(iconView, @selector(overlayView));

        [UIView animateWithDuration:kOverlayDuration animations:^{
            overlayView.alpha = 0.f;
        } completion:^(BOOL finished) {
            if (finished) {
                [overlayView removeFromSuperview];
                [overlayView release];
                objc_setAssociatedObject(iconView, @selector(overlayView), nil, OBJC_ASSOCIATION_ASSIGN);
            }
        }];
    });
}

- (void)_insertPlaceholders
{
    if (_hasPlaceholders) {
        return;
    }
    // Create a layout of placeholders. It has icons in positions where icons should be, but we need to ensure it isn't placed over a icon already there
    STKIconLayout *placeHolderLayout = [STKIconLayoutHandler layoutForPlaceholdersInLayout:_appearingIconLayout withPosition:[self _locationMaskForIcon:_centralIcon]];
    SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
    SBIconListView *listView = STKListViewForIcon(_centralIcon);

    [placeHolderLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconView *iconView = [[[objc_getClass("SBIconView") alloc] initWithDefaultSize] autorelease];
        iconView.delegate = self;
        [iconView setIcon:icon];

        CGPoint newOrigin = [self _targetOriginForIconAtPosition:position distanceFromCentre:[_appearingIconLayout iconsForPosition:position].count + index + 1];
        iconView.frame = (CGRect){newOrigin, iconView.frame.size};

        [self _setAlpha:0.f forLabelAndShadowOfIconView:iconView];
        // Add the icon view to the main icon view layout
        [_iconViewLayout addIcon:iconView toIconsAtPosition:position];

        if (!_iconsHiddenForPlaceholders) {
            _iconsHiddenForPlaceholders = [[STKIconLayout alloc] init];
        }
        iconView.alpha = 0.f;
        [centralIconView insertSubview:iconView belowSubview:centralIconView.iconImageView];
        if (![centralIconView isInDock]) {
            for (SBIcon *ic in [listView icons]) {
                SBIconView *displacedView = [self _iconViewForIcon:ic];
                if (CGRectIntersectsRect(displacedView.frame, [centralIconView convertRect:iconView.frame toView:displacedView.superview])) {
                    [_iconsHiddenForPlaceholders addIcon:displacedView.icon toIconsAtPosition:position];        
                    displacedView.alpha = 0.f;
                    break;
                }
            }
        }
        [UIView animateWithDuration:kOverlayDuration animations:^{ 
            iconView.alpha = 1.f;
        }];
    }];

    if ([centralIconView isInDock]) {
        [_iconViewLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
            if (!iconView.icon.isPlaceholder) {
                return;
            }
            CGPoint targetOrigin = [self _targetOriginForIconAtPosition:position distanceFromCentre:idx + 1];
            CGRect targetFrame = (CGRect){targetOrigin, iconView.frame.size};
            targetFrame = [iconView.superview convertRect:targetFrame toView:[_iconController currentRootIconList]];
            [[_iconController currentRootIconList] makeIconViewsPerformBlock:^(SBIconView *mainListViewIconView) {
                if (CGRectIntersectsRect(targetFrame, mainListViewIconView.frame)) {
                    mainListViewIconView.alpha = 0.f;
                    [_iconsHiddenForPlaceholders addIcon:mainListViewIconView.icon toIconsAtPosition:STKLayoutPositionTop];
                }
            }];
        }];
    }
    _hasPlaceholders = YES;
}

- (void)_removePlaceholders
{
    if (!_hasPlaceholders) {
        return;
    }
    NSMutableArray *viewsToRemove = [NSMutableArray array];

    [UIView animateWithDuration:kOverlayDuration animations:^{
        for (SBIcon *icon in _iconsHiddenForPlaceholders) {
            if (HAS_FE) {
                [self _iconViewForIcon:icon].alpha = 0.2f;
            }
            else {
                [self _iconViewForIcon:icon].alpha = 1.f;                 
            }
        }
        [_iconViewLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *ca, NSUInteger idx) {
            if ([iconView.icon isPlaceholder]) {
                iconView.alpha = 0.f;
                [viewsToRemove addObject:iconView];
            }
        }];
    } completion:^(BOOL finished) {
        if (finished) {
            for (SBIconView *iconView in viewsToRemove) {
                [_iconViewLayout removeIcon:iconView];
                [iconView removeFromSuperview];
            }
            _hasPlaceholders = NO;
        }
    }]; 
}

- (void)showSelectionViewOnIconView:(SBIconView *)iconView
{
    if (_currentSelectionView) {
        return;
    }

    _currentSelectionView = [[STKSelectionView alloc] initWithIconView:iconView
        inLayout:_iconViewLayout
        position:[self _locationMaskForIcon:_centralIcon]
        centralIconView:[self _iconViewForIcon:_centralIcon]
        displacedIcons:_displacedIconLayout];

    _currentSelectionView.delegate = self;
    [_iconViewLayout getPosition:&_selectionViewPosition andIndex:&_selectionViewIndex forIcon:iconView];

    _currentSelectionView.alpha = 0.f;
    [[_iconController contentView] addSubview:_currentSelectionView];
    [_currentSelectionView layoutSubviews];

    [_currentSelectionView scrollToDefaultAnimated:NO];

    [_iconController scrollView].scrollEnabled = NO;

    [UIView animateWithDuration:kAnimationDuration animations:^{
        [_currentSelectionView prepareForDisplay];
        _currentSelectionView.alpha = 1.f;
        SBIconListView *listView = STKListViewForIcon(_centralIcon);
        [listView makeIconViewsPerformBlock:^(SBIconView *iv) { 
            if (iv != [self _iconViewForIcon:_centralIcon]) {
                iv.alpha = 0.f; 
            }
        }];
        // If we're in the dock, hide current list view, else hide the dock. Capiche?
        ((listView == [_iconController dock]) ? [_iconController currentRootIconList] : [_iconController dock].superview).alpha = 0.f;
    } completion:^(BOOL done) {
        if (done && _selectionViewIndex >= 1) {
            NSArray *iconViews = [_iconViewLayout iconsForPosition:_selectionViewPosition];
            SBIconView *firstPlaceholder = nil;
            for (SBIconView *iconView in iconViews) {
                if ([iconView.icon isPlaceholder]) {
                    firstPlaceholder = iconView;
                    break;
                }
            }
            NSUInteger idxOfPlaceholder = [iconViews indexOfObject:firstPlaceholder];
            if (firstPlaceholder && iconView.icon.isPlaceholder && idxOfPlaceholder != _selectionViewIndex) {
                [_currentSelectionView moveToIconView:firstPlaceholder animated:YES completion:nil];
                _selectionViewIndex = idxOfPlaceholder;
            }
        }
    }];
}

- (void)hideSelectionView
{
    if (!_currentSelectionView || _isClosingSelectionView) {
        return;
    }
    _isClosingSelectionView = YES;
    SBIcon *selectedIcon = [_currentSelectionView highlightedIcon];
    [self _addIcon:selectedIcon atIndex:_selectionViewIndex position:_selectionViewPosition];
    [UIView animateWithDuration:kAnimationDuration animations:^{
        // Set the alphas back to normal
        SBIconListView *listView = STKListViewForIcon(_centralIcon);
        CGFloat alphaToSet = (HAS_FE ? 0.2 : 1.f);
        [listView makeIconViewsPerformBlock:^(SBIconView *iv) { 
            if ((iv != [self _iconViewForIcon:_centralIcon]) && !([[_iconsHiddenForPlaceholders allIcons] containsObject:iv.icon]) && !([_hiddenIcons containsObject:iv.icon])) {
                iv.alpha = alphaToSet;
            }
        }];
        ((listView == [_iconController dock]) ? [_iconController currentRootIconList] : [_iconController dock].superview).alpha = 1.f;

        [_currentSelectionView prepareForRemoval];
        _currentSelectionView.alpha = 0.f;

        for (SBIcon *icon in _hiddenIcons) {
            // _hiddenIconsLayout is all new at this point
            [self _iconViewForIcon:icon].alpha = 0.f;
        }
    } completion:^(BOOL done) {
        if (done) {
            [_currentSelectionView removeFromSuperview];
            [_currentSelectionView release];

            [_iconController scrollView].scrollEnabled = YES;
         
            _currentSelectionView = nil;
            _selectionViewPosition = STKLayoutPositionNone;
            _selectionViewIndex = 1337;
            _isClosingSelectionView = NO;
        }
    }];
}

- (void)closeButtonTappedOnSelectionView:(STKSelectionView *)selectionView
{
    [self hideSelectionView];
}

- (void)userTappedHighlightedIconInSelectionView:(STKSelectionView *)selectionView;
{
    [self hideSelectionView];
}

- (void)_addIcon:(SBIcon *)iconToAdd atIndex:(NSUInteger)idx position:(STKLayoutPosition)addPosition
{
    SBIcon *removedIcon = nil;
    if (_isEmpty) {
        if (iconToAdd.isPlaceholder || !(idx < [_iconViewLayout iconsForPosition:addPosition].count)) {
            return;
        }
        SBIconView *iconView = [_iconViewLayout iconsForPosition:addPosition][idx];
        [iconView setIcon:iconToAdd]; // Convert the placeholder icon into a regular app icon. SBIconView <3
        
        [_appearingIconLayout removeAllIcons];
        [_appearingIconLayout release];
        _appearingIconLayout = [[STKIconLayout alloc] init];
        [_appearingIconLayout addIcon:iconToAdd toIconsAtPosition:addPosition];

        [self _setAlpha:1.f forLabelAndShadowOfIconView:iconView];

        _isEmpty = NO;
        _hasPlaceholders = YES; // We already have these, courtesy all the empty icons in the stack. :P
        self.isEditing = YES;
    } 
    else {  // isEmpty == NO
        NSArray *iconViews = [_iconViewLayout iconsForPosition:addPosition];
        if (idx <= (iconViews.count - 1)) {
            SBIconView *iconViewToChange = iconViews[idx];
            BOOL iconToChangeWasPlaceholder = iconViewToChange.icon.isPlaceholder;
            if ((iconToChangeWasPlaceholder && iconToAdd.isPlaceholder) || [iconViewToChange.icon.leafIdentifier isEqualToString:iconToAdd.leafIdentifier]) {
                // If both icons are the same, simply exit.
                // It is better to simply check a BOOL instead of comparing strings, which is why the placeholder check is first
                return;
            }
            if (!iconToChangeWasPlaceholder) {
                removedIcon = iconViewToChange.icon;
            }
            // If `iconToAdd` is a sub-app, change it's icon view to a place holder
            NSUInteger currentSubappIndex;
            STKLayoutPosition currentSubappPosition;
            [_appearingIconLayout getPosition:&currentSubappPosition andIndex:&currentSubappIndex forIcon:iconToAdd];
            if (currentSubappIndex != NSNotFound) {
                STKPlaceholderIcon *placeholder = [[[objc_getClass("STKPlaceholderIcon") alloc] init] autorelease];
                [_appearingIconLayout removeIcon:iconToAdd];

                SBIconView *subAppViewToChange = [_iconViewLayout iconsForPosition:currentSubappPosition][currentSubappIndex];
                [subAppViewToChange setIcon:placeholder];
            }

            // Set the icon!
            [iconViewToChange setIcon:iconToAdd];

            SBIconView *centralView = [self _iconViewForIcon:_centralIcon];
            [centralView bringSubviewToFront:centralView.iconImageView];
            [centralView sendSubviewToBack:iconViews[idx]];

            if (iconToAdd.isPlaceholder) {
                // Remove the icon that is to be replaced with a placeholder from _appearingIcons
                [_appearingIconLayout removeIcon:removedIcon fromIconsAtPosition:addPosition];
                [self _setAlpha:0.f forLabelAndShadowOfIconView:iconViewToChange];

                // Setting this makes the icon view be removed as a part of the placeholder removal routine.
                _hasPlaceholders = YES;
                [self _addOverlayOnIconView:iconViewToChange];
            }
            else {
                [_appearingIconLayout setIcon:iconToAdd atIndex:idx position:addPosition];
                [self _setAlpha:1.f forLabelAndShadowOfIconView:iconViewToChange];
                [self _addOverlays];
            } 
            if (iconToChangeWasPlaceholder) {
                [_closingAnimationOpQueue stk_addOperationToRunOnMainThreadWithBlock:^{
                    // Since we're converting a placholder icon, find the icon hidden underneath it, and un-hide it. Capiche?
                    SBIcon *hiddenIcon = [self _displacedIconAtPosition:addPosition intersectingAppearingIconView:iconViewToChange];
                    if (hiddenIcon) {
                        SBIconView *hiddenIconView = [self _iconViewForIcon:hiddenIcon];
                        hiddenIconView.alpha = 1.f;
                    }
                }];
            }
            // If _appearingIconLayout has count 0, we've removed all non-placeholders from it in the if (iconToAdd.isPlaceholder) check
            _isEmpty = ([_appearingIconLayout totalIconCount] == 0);            
            if (_isEmpty) {
                // We are definitely not editing now, since the stack has switched over to imitate an empty stack
                _isEditing = NO;
                _hasPlaceholders = NO;

                [_closingAnimationOpQueue stk_addOperationToRunOnMainThreadWithBlock:^{
                    for (SBIcon *icon in _iconsHiddenForPlaceholders) {
                        [self _iconViewForIcon:icon].alpha = 1.f;
                    }
                    [self _iconViewForIcon:_centralIcon].transform = CGAffineTransformMakeScale(1.f, 1.f);
                }];

                [_postCloseOpQueue stk_addOperationToRunOnMainThreadWithBlock:^{
                    MAP([_iconsHiddenForPlaceholders allIcons], ^(SBIcon *icon) {
                        [self _iconViewForIcon:icon].alpha = 1.f;
                    });
                }];
            }
        }
    }

    [self.delegate stack:self didAddIcon:(iconToAdd.isPlaceholder ? nil : iconToAdd) removingIcon:removedIcon atPosition:addPosition index:idx];
}

- (SBIcon *)_displacedIconAtPosition:(STKLayoutPosition)position intersectingAppearingIconView:(SBIconView *)iconView
{
    for (SBIcon *dispIcon in [_displacedIconLayout iconsForPosition:position]) {
        if (CGRectIntersectsRect([self _iconViewForIcon:dispIcon].frame, ([iconView.superview convertRect:iconView.frame toView:[self _iconViewForIcon:dispIcon].superview]))) {
            return dispIcon;
        }
    }

    return nil;
}

#pragma mark - SBIconViewDelegate
- (void)iconTouchBegan:(SBIconView *)iconView
{
    [iconView setHighlighted:YES];
}

- (void)icon:(SBIconView *)iconView touchEnded:(BOOL)arg2
{
    [iconView setHighlighted:NO];
    _longPressed = NO;
}

- (void)iconTapped:(SBIconView *)iconView
{
    if (!iconView.userInteractionEnabled || [iconView isGhostly]) {
        return;
    }
    if (_longPressed) {
        _longPressed = NO;
        return;
    }
    if (![iconView.icon.leafIdentifier isEqual:_centralIcon.leafIdentifier] && (_isEditing || [iconView.icon.leafIdentifier isEqualToString:STKPlaceholderIconIdentifier])) {
        if ([self.delegate respondsToSelector:@selector(stack:didReceiveTapOnPlaceholderIconView:)]) {
            [self.delegate stack:self didReceiveTapOnPlaceholderIconView:iconView];
        }
        return;
    }
    if (_isEditing) {
        self.isEditing = NO;
        return;
    }
    [iconView setHighlighted:YES delayUnhighlight:YES];
    if ([self.delegate respondsToSelector:@selector(stack:didReceiveTapOnIconView:)]) {
        [self.delegate stack:self didReceiveTapOnIconView:iconView];
    }
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    [iconView setHighlighted:NO];
    self.isEditing = !(self.isEditing);

    _longPressed = YES;
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return iconView.userInteractionEnabled; 
}

- (BOOL)iconPositionIsEditable:(SBIconView *)iconView
{
    return NO;
}

- (BOOL)iconViewDisplaysBadges:(SBIconView *)iconView
{    
    return [_iconController iconViewDisplaysBadges:iconView];   
}

@end
