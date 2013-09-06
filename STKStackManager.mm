#import "STKStackManager-Private.h"
#import "STKIconLayoutHandler.h"
#import "STKSelectionView.h"
#import "STKIdentifiedOperation.h"

#import "SBIconModel+Additions.h"
#import "SBIconViewMap+AcervosSafety.h"
#import "NSOperationQueue+STKMainQueueDispatch.h"
#import "STKPreferences.h"

#import <objc/runtime.h>

#define kSTKIconModelLayoutOpID @"STKIconModelLayoutOpID"

@implementation STKStackManager 
{
    SBIcon                   *_centralIcon;
    STKIconLayout            *_appearingIconsLayout;
    STKIconLayout            *_displacedIconsLayout;
    STKIconLayout            *_offScreenIconsLayout;
    STKIconLayout            *_iconViewsLayout;
    STKInteractionHandler     _interactionHandler;

    NSOperationQueue         *_closingAnimationOpQueue;
    NSOperationQueue         *_postCloseOpQueue;

    STKIconCoordinates        _iconCoordinates;

    CGFloat                   _distanceRatio;
    CGFloat                   _popoutCompensationRatio;
    CGFloat                   _lastDistanceFromCenter;

    BOOL                      _longPressed; 
    BOOL                      _needsLayout;
    BOOL                      _layoutDiffersFromFile;
    BOOL                      _closingForSwitcher;
    BOOL                      _hasPlaceHolders;
    BOOL                      _isClosingSelectionView;

    UISwipeGestureRecognizer *_swipeRecognizer;
    UITapGestureRecognizer   *_tapRecognizer;

    id<SBIconViewDelegate>    _previousDelegate;

    STKSelectionView         *_currentSelectionView;
    STKIconLayout            *_placeHolderViewsLayout;
    STKIconLayout            *_iconsHiddenForPlaceHolders;

    STKLayoutPosition         _selectionViewPosition;
    NSUInteger                _selectionViewIndex;

    BOOL                      _hasLayoutOp;
    NSMutableArray           *_iconsToHideOnClose;
    NSMutableArray           *_iconsToShowOnClose;

    SBIconController         *_iconController;
}

@synthesize currentIconDistance = _lastDistanceFromCenter;

+ (BOOL)isValidLayoutAtPath:(NSString *)path
{
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!dict) {
        return NO;
    }

    SBIconModel *model = (SBIconModel *)[[objc_getClass("SBIconController") sharedInstance] model];
    NSArray *stackIconIDs = dict[STKStackManagerStackIconsKey];

    if (![model expectedIconForDisplayIdentifier:dict[STKStackManagerCentralIconKey]] || !stackIconIDs) {
        return NO;
    }

    NSUInteger count = 0;
    for (NSString *ident in stackIconIDs) {
        if ([model expectedIconForDisplayIdentifier:ident]) {
            count++;
        }
    }

    if (count == 0) {
        return NO;
    }

    return YES;
}


#pragma mark - Public Methods
- (instancetype)initWithContentsOfFile:(NSString *)file
{
    _iconController = [objc_getClass("SBIconController") sharedInstance];
    SBIconModel *model = [(SBIconController *)_iconController model];

    NSDictionary *attributes = [NSDictionary dictionaryWithContentsOfFile:file];
    NSDictionary *customLayout = attributes[STKStackManagerCustomLayoutKey];
    SBIcon *centralIcon = [model expectedIconForDisplayIdentifier:attributes[STKStackManagerCentralIconKey]];

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
            NSLog(@"[%@] Couldn't get icon for identifier %@. Confirm that the ID is correct and the app is installed.", kSTKTweakName, identifier);
        }
    }

    if (!centralIcon) {
        NSLog(@"[%@] Central Icon: %@ doesn't exist, dying quietly...", kSTKTweakName, attributes[STKStackManagerCentralIconKey]);
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

        [icons retain]; // Make sure it's not released until we're done with it

        _centralIcon = [centralIcon retain];
        STKPositionMask mask = [self _locationMaskForIcon:_centralIcon];

        if (!icons || icons.count == 0) {
            _appearingIconsLayout = [[STKIconLayoutHandler emptyLayoutForIconAtPosition:mask] retain];
            _isEmpty = YES;
        }
        else {
            _appearingIconsLayout = [[STKIconLayoutHandler layoutForIcons:icons aroundIconAtPosition:mask] retain];
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

    STKIconCoordinates currentCoords = [STKIconLayoutHandler coordinatesForIcon:centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    STKIconCoordinates savedCoords;

    // Make sure the objects do exist since 0 is a valid coordinate that many icons may have.
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
        _appearingIconsLayout = [layout retain];
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
    _displacedIconsLayout = [[STKIconLayoutHandler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconsLayout] retain];
    _iconCoordinates = [STKIconLayoutHandler coordinatesForIcon:_centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];

    _postCloseOpQueue = [[NSOperationQueue alloc] init];
    [_postCloseOpQueue setSuspended:YES];
    [_postCloseOpQueue setMaxConcurrentOperationCount:1];

    _closingAnimationOpQueue = [[NSOperationQueue alloc] init];
    [_closingAnimationOpQueue setSuspended:YES];
    [_closingAnimationOpQueue setMaxConcurrentOperationCount:1];

    [self _calculateDistanceRatio];
    [self _findIconsWithOffScreenTargets];

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

    if (_previousDelegate) {
        [self _iconViewForIcon:_centralIcon].delegate = _previousDelegate;
    }
    
    if (_interactionHandler) {
        [_interactionHandler release];
    }

    [_centralIcon release];
    [_appearingIconsLayout release];
    [_displacedIconsLayout release];
    [_offScreenIconsLayout release];

    [_postCloseOpQueue cancelAllOperations];
    [_postCloseOpQueue release];

    [_closingAnimationOpQueue cancelAllOperations];
    [_closingAnimationOpQueue release];

    [self _cleanupGestureRecognizers];

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super dealloc];
}

- (id)init
{
    NSAssert(NO, @"**** You MUST use -[STKStackManager initWithCentralIcon:stackIcons:]");
    return nil;
}

- (void)saveLayoutToFile:(NSString *)file
{
    if (_isEmpty) {
        return;
    }

    @synchronized(self) {
        NSMutableDictionary *dictionaryRepresentation = [[[_appearingIconsLayout dictionaryRepresentation] mutableCopy] autorelease];
        dictionaryRepresentation[@"xPos"] = @(_iconCoordinates.xPos);
        dictionaryRepresentation[@"yPos"] = @(_iconCoordinates.yPos);

        NSDictionary *fileDict = @{ STKStackManagerCentralIconKey  : _centralIcon.leafIdentifier,
                                    STKStackManagerStackIconsKey   : [[_appearingIconsLayout allIcons] valueForKeyPath:@"leafIdentifier"],
                                    STKStackManagerCustomLayoutKey : dictionaryRepresentation};

        [fileDict writeToFile:file atomically:YES];

        _layoutDiffersFromFile = NO;
    }
}

- (void)recalculateLayouts
{
    NSArray *stackIcons = [_appearingIconsLayout allIcons];

    STKIconCoordinates current = [STKIconLayoutHandler coordinatesForIcon:_centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];

    [_displacedIconsLayout release];

    STKPositionMask mask = [self _locationMaskForIcon:_centralIcon];
    STKIconLayout *suggestedLayout = nil;

    if (_isEmpty || [_appearingIconsLayout allIcons].count == 0) {
        _isEmpty = YES;
        [_appearingIconsLayout release];
        _appearingIconsLayout = [[STKIconLayoutHandler emptyLayoutForIconAtPosition:mask] retain];
    }
    else if (!(EQ_COORDS(current, _iconCoordinates)) && ([STKIconLayoutHandler layout:_appearingIconsLayout requiresRelayoutForPosition:mask suggestedLayout:&suggestedLayout])) {
        [_appearingIconsLayout release];
        if (!suggestedLayout) {
            _appearingIconsLayout = [[STKIconLayoutHandler layoutForIcons:stackIcons aroundIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
        }
        else {
            _appearingIconsLayout = [suggestedLayout retain];
        }

        if (_interactionHandler) {
            _interactionHandler(self, nil, YES, nil);
        }
    }
    else if (EQ_COORDS(current, _iconCoordinates) == NO) {
        // The coords have changed, but a re-layout isn't necessary
        _iconCoordinates = current;
        if (_interactionHandler) {
            _interactionHandler(self, nil, YES, nil);
        }
    }

    [self _setup];

    if (_hasSetup) {
        [self cleanupView];
        [self setupPreview];
    }
}

- (void)removeIconFromAppearingIcons:(SBIcon *)icon
{
    [_appearingIconsLayout removeIcon:icon];
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
    _iconViewsLayout = [[STKIconLayout alloc] init];
    
    SBIconView *centralIconView = [[objc_getClass("SBIconViewMap") homescreenMap] safeIconViewForIcon:_centralIcon];
    centralIconView.userInteractionEnabled = YES;

    [_appearingIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconView *iconView = [[[objc_getClass("SBIconView") alloc] initWithDefaultSize] autorelease];
        iconView.location = (SBIconViewLocation)1337;
        
        [iconView setIcon:icon];
        [iconView setDelegate:self];

        iconView.frame = centralIconView.bounds;
        [self _setAlpha:0.f forLabelAndShadowOfIconView:iconView];
        if (!_isEmpty && _showsPreview) {
            iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);
        }

        [_iconViewsLayout addIcon:iconView toIconsAtPosition:position];

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

    MAP([_iconViewsLayout allIcons], ^(SBIconView *iconView) {
        [iconView removeFromSuperview];
    });

    [_iconViewsLayout removeAllIcons];
    [_iconViewsLayout release];
    _iconViewsLayout = nil;

    _hasSetup = NO;
}

#pragma mark - Preview Handling
- (void)setupPreview
{
    [self setupViewIfNecessary];

    [_iconViewsLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
        CGRect frame = [self _iconViewForIcon:_centralIcon].bounds;
        CGPoint newOrigin = frame.origin;

        // Check if it's the last object
        if (!_isEmpty && _showsPreview && idx == currentArray.count - 1) {
            if (!_closingForSwitcher && ![[self _iconViewForIcon:_centralIcon] isGhostly]) {
                iconView.alpha = 1.f;
            }

            // This is probably how the rest of the code should've been written
            CGFloat *memberToModify = ((position == STKLayoutPositionTop || position == STKLayoutPositionBottom) ? &newOrigin.y : &newOrigin.x);

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
            // Scale the icon back down to the smaller size, only if there indeed _are_ any icons
            iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);
        }

        // Hide the labels and shadows
        [self _setAlpha:0.f forLabelAndShadowOfIconView:iconView];
        iconView.userInteractionEnabled = NO;

        _closingForSwitcher = NO;
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
    [self _findIconsWithOffScreenTargets];
}

- (void)touchesDraggedForDistance:(CGFloat)distance
{
    if (_isExpanded && ![[_iconController scrollView] isDragging]) {
        return;
    }

    CGFloat alpha = STKAlphaFromDistance(_lastDistanceFromCenter);

    // [_iconController prepareToGhostCurrentPageIconsForRequester:kGhostlyRequesterID skipIcon:_centralIcon];
    [self _setGhostlyAlphaForAllIcons:alpha excludingCentralIcon:YES];
    [self _setPageControlAlpha:alpha];

    BOOL hasVerticalIcons = ([_appearingIconsLayout iconsForPosition:STKLayoutPositionTop].count > 0) || ([_appearingIconsLayout iconsForPosition:STKLayoutPositionBottom].count > 0);
    [self _moveAllIconsInRespectiveDirectionsByDistance:distance performingTask:^(SBIconView *iv, STKLayoutPosition pos, NSUInteger idx) {
    	if (idx == 0) {
    	    if (hasVerticalIcons && (pos == STKLayoutPositionTop || pos == STKLayoutPositionBottom)) {
    	        _lastDistanceFromCenter = fabsf(iv.frame.origin.y - [self _iconViewForIcon:_centralIcon].bounds.origin.y);
    	    }
    	    else if (!hasVerticalIcons && (pos == STKLayoutPositionLeft || pos == STKLayoutPositionRight)) {
    	       _lastDistanceFromCenter = fabsf(iv.frame.origin.x - [self _iconViewForIcon:_centralIcon].bounds.origin.x);
    	    }
    	}

        if (!_isEmpty) {
            if (iv.alpha <= 0.f) {
                iv.alpha = 1.f;
            }
            [self _setAlpha:(1 - alpha) forLabelAndShadowOfIconView:iv];

            if (_showsPreview) {
                CGFloat midWayDistance = STKGetCurrentTargetDistance() / 2.0;
                if (_lastDistanceFromCenter <= midWayDistance) {
                    // If the icons are past the halfway mark, start increasing/decreasing their scale.
                    // This looks beatuiful. Yay me.
                    CGFloat stackIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kStackPreviewIconScale);
                    iv.iconImageView.transform = CGAffineTransformMakeScale(stackIconTransformScale, stackIconTransformScale);
                    
                
                    CGFloat centralIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kCentralIconPreviewScale);
                    [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(centralIconTransformScale, centralIconTransformScale);
                }
                else {      
                    [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
                    iv.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
                }
            }
        }
        else {
            iv.alpha = (1 - alpha);
        }      
    }];
}

- (void)touchesEnded
{
    if (_lastDistanceFromCenter >= kEnablingThreshold && !_isExpanded) {
        // Set this now, not waiting for the animation to complete, so anyone asking questions gets the right answer... LOL
        _isExpanded = YES;
        [self openStack];
    }
    else {
        [self _animateToClosedPositionWithCompletionBlock:^{
            if (_interactionHandler) {
                _interactionHandler(self, nil, NO, nil);
            }   
        } duration:kAnimationDuration animateCentralIcon:NO forSwitcher:NO];
    }
}
 
- (void)closeStackWithCompletionHandler:(void(^)(void))completionHandler
{
    [self _animateToClosedPositionWithCompletionBlock:^{
        if (completionHandler) {
            completionHandler();
        }
    } duration:kAnimationDuration animateCentralIcon:YES forSwitcher:NO];
}

- (void)closeForSwitcherWithCompletionHandler:(void(^)(void))completionHandler;
{
    [self _animateToClosedPositionWithCompletionBlock:completionHandler duration:kAnimationDuration animateCentralIcon:YES forSwitcher:YES];
}

- (void)openStack
{
    [self _animateToOpenPositionWithDuration:kAnimationDuration];
}

- (void)closeStack
{
    [self closeStackWithCompletionHandler:nil];
}

- (BOOL)handleHomeButtonPress
{
    BOOL didIntercept = NO;
    if (_currentSelectionView) {
        [self _hideActiveSelectionView];
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
        [self _addOverlays];
        [self _insertPlaceHolders];
    }
    else {
        [self _hideActiveSelectionView];
        [self _removeOverlays];
        [self _removePlaceHolders];
    }

    _isEditing = editing;
}

- (void)setStackIconAlpha:(CGFloat)alpha
{
    MAP([_iconViewsLayout allIcons], ^(SBIconView *iv) {
        iv.alpha = alpha;
    });
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////        HAXX        //////////////////////////////////////////////////////////

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (_currentSelectionView && CGRectContainsPoint(_currentSelectionView.frame, point)) {
        return _currentSelectionView;
    }

    CGRect centralIconViewFrame = [self _iconViewForIcon:_centralIcon].bounds;
    
    if (CGRectContainsPoint(centralIconViewFrame, point)) {
        return [self _iconViewForIcon:_centralIcon];
    } 

    for (SBIconView *iconView in [_iconViewsLayout allIcons]) {
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

        [_iconViewsLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
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

        [_displacedIconsLayout enumerateIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
            SBIconView *iconView = [self _iconViewForIcon:icon];
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _displacedOriginForIcon:icon withPosition:position];
            iconView.frame = newFrame;
        }];

        [self _setPageControlAlpha:0];

        [self _setGhostlyAlphaForAllIcons:0.f excludingCentralIcon:YES];

        [_offScreenIconsLayout enumerateIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition pos) {
            [self _iconViewForIcon:icon].alpha = 0.f;
        }];
        
    } completion:^(BOOL finished) {
        if (finished) {
            SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
            _previousDelegate = centralIconView.delegate;
            centralIconView.delegate = self;
            centralIconView.userInteractionEnabled = YES;

            [self _setupGestureRecognizers];

            _isExpanded = YES;
        }
    }];
}

#pragma mark - Close Animation
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock duration:(NSTimeInterval)duration animateCentralIcon:(BOOL)animateCentralIcon forSwitcher:(BOOL)forSwitcher
{
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
    
    // Make sure we're not in the editing state
    self.isEditing = NO;
    // Aand remove those F**king placeholders
    [self _removePlaceHolders];

    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        _closingForSwitcher = forSwitcher;
        [self setupPreview];

        // Set the alphas back to original
        [self _setGhostlyAlphaForAllIcons:0.999f excludingCentralIcon:NO];
        [self _setPageControlAlpha:1];

        // Bring the off screen icons back to life! :D
        [_offScreenIconsLayout enumerateIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition pos) {
            [self _iconViewForIcon:icon].alpha = 1.f;
        }];

        [_closingAnimationOpQueue setSuspended:NO];
        [_closingAnimationOpQueue waitUntilAllOperationsAreFinished];
        [_closingAnimationOpQueue setSuspended:YES];

        if (!animateCentralIcon) {
            centralView.transform = CGAffineTransformMakeScale(scale, scale);
        }

    } completion:^(BOOL finished) {
        if (finished) {
            // Remove the icon view's delegates
            for (SBIconView *iconView in [_iconViewsLayout allIcons]) {
                iconView.delegate = nil;
            }

            // XXX: BUGFIX for SBIconListView BS
            [self _setGhostlyAlphaForAllIcons:.9999999f excludingCentralIcon:NO]; // .999f is necessary, unfortunately. A weird 1.0->0.0->1.0 alpha flash happens otherwise
            [self _setGhostlyAlphaForAllIcons:1.f excludingCentralIcon:NO]; // Set it back to 1.f, fix a pain in the ass bug
            
            [_iconController cleanUpGhostlyIconsForRequester:kGhostlyRequesterID];

            [_offScreenIconsLayout release];
            _offScreenIconsLayout = nil;

            if (_isEmpty || !_showsPreview) {
                // We can remove the place holder icon views if the stack is empty. No need to have 4 icon views hidden behind every damn icon.
                [self cleanupView];
                
                [_offScreenIconsLayout removeAllIcons];
                [_offScreenIconsLayout release];
                _offScreenIconsLayout = nil;
                
                if (_isEmpty) {
                    [_appearingIconsLayout removeAllIcons];
                    [_appearingIconsLayout release];
                    _appearingIconsLayout = nil;    
                }
                
                [_displacedIconsLayout removeAllIcons];
                [_displacedIconsLayout release];
                _displacedIconsLayout = nil;

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

    [_displacedIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconView *iconView = [self _iconViewForIcon:icon]; // Get the on-screen icon view from the list view.
        CGRect iconFrame = iconView.frame;
        CGRect newFrame = iconView.frame;
        
        CGPoint originalOrigin = [listView originForIcon:icon];
        CGPoint targetOrigin = [self _displacedOriginForIcon:icon withPosition:position]; 

        NSUInteger appearingIconsCount = [_appearingIconsLayout iconsForPosition:position].count;
        CGFloat factoredDistance = (distance * appearingIconsCount);  // Factor the distance up by the number of icons that are coming in at that position
        CGFloat horizontalFactoredDistance = factoredDistance * _distanceRatio; // The distance to be moved horizontally is slightly different than vertical, multiply it by the ratio to have them work perfectly. :)
        
        CGFloat *targetCoord, *currentCoord, *newCoord, *originalCoord;
        CGFloat moveDistance;

        if (position == STKLayoutPositionTop || position == STKLayoutPositionBottom) {
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
    [_iconViewsLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
        CGRect iconFrame = iconView.frame;
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _targetOriginForIconAtPosition:position distanceFromCentre:idx + 1];
        CGRect centralFrame = [self _iconViewForIcon:_centralIcon].bounds;

        if (task) {
            task(iconView, position, idx);
        }

        CGFloat negator = ((position == STKLayoutPositionTop || position == STKLayoutPositionLeft) ? -1.f : 1.f);
        CGFloat distanceRatio = 1.f;

        CGFloat *targetCoord, *currentCoord, *newCoord, *centralCoord;
        CGFloat moveDistance = distance * negator;

        if (position == STKLayoutPositionTop || position == STKLayoutPositionBottom) {
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

        moveDistance *= distanceRatio;

        CGFloat multFactor = (IS_LESSER((*currentCoord + moveDistance), *targetCoord, position) ? (idx + 1) : 1);
        CGFloat popComp = (((idx == currentArray.count - 1) && !(_isEmpty || !_showsPreview)) ? ((*targetCoord - kPopoutDistance * negator) / *targetCoord) : 1.f);

        moveDistance *= (multFactor * popComp);


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

    UIView *contentView = [[objc_getClass("SBUIController") sharedInstance] contentView];
    [contentView addGestureRecognizer:_swipeRecognizer];
    [contentView addGestureRecognizer:_tapRecognizer];
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

        for (SBIconView *iconView in [_iconViewsLayout allIcons]) {
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
    [self closeStackWithCompletionHandler:^{ if (_interactionHandler) _interactionHandler(self, nil, NO, nil); }];
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
    return [[objc_getClass("SBIconViewMap") homescreenMap] mappedIconViewForIcon:icon];
}

- (STKPositionMask)_locationMaskForIcon:(SBIcon *)icon
{
    STKPositionMask mask = 0x0;
    
    if (!icon) {
        return mask;
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
    STKIconCoordinates centralCoords = [STKIconLayoutHandler coordinatesForIcon:_centralIcon withOrientation:[UIApplication sharedApplication].statusBarOrientation];
    SBIconListView *listView = STKListViewForIcon(_centralIcon);

    CGPoint ret = CGPointZero;

    switch (position) {
        case STKLayoutPositionTop: {
            NSUInteger newY = (centralCoords.yPos - distance); // New Y will be `distance` units above original y
            ret =  [listView originForIconAtX:centralCoords.xPos Y:newY];
            break;
        }
        case STKLayoutPositionBottom: {
            NSUInteger newY = (centralCoords.yPos + distance); // New Y will be below
            ret = [listView originForIconAtX:centralCoords.xPos Y:newY]; 
            break;
        }
        case STKLayoutPositionLeft: {
            NSUInteger newX = (centralCoords.xPos - distance); // New X has to be `distance` points to left, so subtract
            ret = [listView originForIconAtX:newX Y:centralCoords.yPos];
            break;
        }
        case STKLayoutPositionRight: {
            NSUInteger newX = (centralCoords.xPos + distance); // Inverse of previous, hence add to original coordinate
            ret = [listView originForIconAtX:newX Y:centralCoords.yPos];
            break;
        }

        default: {
            break;
        }
    }

    ret = [[self _iconViewForIcon:_centralIcon] convertPoint:ret fromView:listView];

    return ret;
}

- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position usingLayout:(STKIconLayout *)layout
{
    // Calculate the positions manually, as -[SBIconListView originForIconAtX:Y:] only gives coordinates that will be on screen, but allow for off-screen icons too.
    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    SBIconView *iconView = [self _iconViewForIcon:icon];
    
    CGPoint originalOrigin = [listView originForIcon:icon]; // Use the original location as a reference, as the iconview might have been displaced.
    CGRect originalFrame = (CGRect){{originalOrigin.x, originalOrigin.y}, {iconView.frame.size.width, iconView.frame.size.height}};
    
    CGPoint returnPoint;
    NSInteger multiplicationFactor = [layout iconsForPosition:position].count;
    
    switch (position) {
        case STKLayoutPositionTop: {
            returnPoint.x = originalFrame.origin.x;
            returnPoint.y = originalFrame.origin.y - ((originalFrame.size.height + [listView verticalIconPadding]) * multiplicationFactor);
            break;
        }
        case STKLayoutPositionBottom: {
            returnPoint.x = originalFrame.origin.x;
            returnPoint.y = originalFrame.origin.y + ((originalFrame.size.height + [listView verticalIconPadding]) * multiplicationFactor);    
            break;
        }
        case STKLayoutPositionLeft: {
            returnPoint.y = originalFrame.origin.y;
            returnPoint.x = originalFrame.origin.x - ((originalFrame.size.width + [listView horizontalIconPadding]) * multiplicationFactor);
            break;
        }
        case STKLayoutPositionRight: {
            returnPoint.y = originalFrame.origin.y;
            returnPoint.x = originalFrame.origin.x + ((originalFrame.size.width + [listView horizontalIconPadding]) * multiplicationFactor);
            break;
        }
    }
    
    return returnPoint;
}

- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position
{
    return [self _displacedOriginForIcon:icon withPosition:position usingLayout:_appearingIconsLayout];
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
    _popoutCompensationRatio = ((_isEmpty || _showsPreview) ? 1.f : (verticalDistance / (verticalDistance - kPopoutDistance))); // This is the ratio of the target distance of a stack icon to a displaced icon, respectively
}

- (void)_findIconsWithOffScreenTargets
{
    [_offScreenIconsLayout release];
    _offScreenIconsLayout = [[STKIconLayout alloc] init]; 

    CGRect listViewBounds = STKListViewForIcon(_centralIcon).bounds;
    [_displacedIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        CGPoint target = [self _displacedOriginForIcon:icon withPosition:position];
        CGRect targetRect = (CGRect){{target.x, target.y}, [self _iconViewForIcon:icon].frame.size};

        switch (position) {
            case STKLayoutPositionTop: {
                if (CGRectGetMaxY(targetRect) <= (listViewBounds.origin.y + 20)) {
                    // Add 20 to account for status bar frame
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }

            case STKLayoutPositionBottom: {
                if (target.y + 10 > listViewBounds.size.height) {
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }

            case STKLayoutPositionLeft: {
                if (CGRectGetMaxX(targetRect) <= listViewBounds.origin.y) {
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }

            case STKLayoutPositionRight: {
                if (CGRectGetMinX(targetRect) >= CGRectGetWidth(listViewBounds)) {
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }

            default: {
                ;
            }
        }
    }];
}

#pragma mark - Alpha Shit

- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral
{
    if (alpha >= 1.f) {
        [_iconController setCurrentPageIconsGhostly:NO forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];
    }
    else if (alpha <= 0.f) {
        [_iconController setCurrentPageIconsGhostly:YES forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];   
    }
    else {
        [_iconController setCurrentPageIconsPartialGhostly:alpha forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];
    }

    MAP(_offScreenIconsLayout.bottomIcons, ^(SBIcon *icon) {
        [self _iconViewForIcon:icon].alpha = alpha;
    })
}

- (void)_setAlpha:(CGFloat)alpha forLabelAndShadowOfIconView:(SBIconView *)iconView
{
    ((UIImageView *)[iconView valueForKey:@"_shadow"]).alpha = alpha;
    [iconView setIconLabelAlpha:alpha];
    ((UIView *)[iconView valueForKey:@"_accessoryView"]).alpha = alpha;
}

- (void)_setPageControlAlpha:(CGFloat)alpha
{
    [_iconController setPageControlAlpha:alpha];
}


#pragma mark - Editing Handling
- (void)_addOverlays
{
    for (SBIconView *iconView in [_iconViewsLayout allIcons]) {
        if (iconView.icon.isPlaceholder) {
            continue;
        }

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
}

- (void)_removeOverlays
{
    MAP([_iconViewsLayout allIcons], ^(SBIconView *iconView) {
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

- (void)_insertPlaceHolders
{
    if (_hasPlaceHolders) {
        return;
    }
    // Create a layout of placeholders. It has icons in positions where icons should be, but it is left to us to make sure it isn't placed over a icon already there
    STKIconLayout *placeHolderLayout = [STKIconLayoutHandler layoutForPlaceHoldersInLayout:_appearingIconsLayout withPosition:[self _locationMaskForIcon:_centralIcon]];
    SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
    SBIconListView *listView = STKListViewForIcon(_centralIcon);

    [placeHolderLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconView *iconView = [[[objc_getClass("SBIconView") alloc] initWithDefaultSize] autorelease];
        iconView.delegate = self;
        [iconView setIcon:icon];

        CGPoint newOrigin = [self _targetOriginForIconAtPosition:position distanceFromCentre:[_appearingIconsLayout iconsForPosition:position].count + index + 1];
        iconView.frame = (CGRect){newOrigin, iconView.frame.size};

        [self _setAlpha:0.f forLabelAndShadowOfIconView:iconView];

        // Add the icon view to the main icon view layout
        [_iconViewsLayout addIcon:iconView toIconsAtPosition:position];

        if (!_iconsHiddenForPlaceHolders) {
            _iconsHiddenForPlaceHolders = [[STKIconLayout alloc] init];
        }

        iconView.alpha = 0.f;
        [centralIconView insertSubview:iconView belowSubview:centralIconView.iconImageView];

        for (SBIcon *ic in [listView icons]) {
            SBIconView *displacedView = [self _iconViewForIcon:ic];
            if (CGRectIntersectsRect(displacedView.frame, [centralIconView convertRect:iconView.frame toView:displacedView.superview])) {
                [_iconsHiddenForPlaceHolders addIcon:displacedView.icon toIconsAtPosition:position];        
                displacedView.alpha = 0.f;
                break;
            }
        }

        [UIView animateWithDuration:kOverlayDuration animations:^{ 
            iconView.alpha = 1.f;
        }];
    }];

    _hasPlaceHolders = YES;
}

- (void)_removePlaceHolders
{
    if (!_hasPlaceHolders) {
        return;
    }
    NSMutableArray *viewsToRemove = [NSMutableArray array];

    [UIView animateWithDuration:kOverlayDuration animations:^{
        MAP([_iconsHiddenForPlaceHolders allIcons], ^(SBIcon *icon){ [self _iconViewForIcon:icon].alpha = 1.f; });

        [_iconViewsLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *ca, NSUInteger idx) {
            if ([iconView.icon.leafIdentifier isEqualToString:STKPlaceHolderIconIdentifier]) {
                iconView.alpha = 0.f;
                [viewsToRemove addObject:iconView];
            }
        }];
    } completion:^(BOOL finished) {
        if (finished) {
            for (SBIconView *iconView in viewsToRemove) {
                [_iconViewsLayout removeIcon:iconView];
                [iconView removeFromSuperview];
            }
            _hasPlaceHolders = NO;
        }
    }]; 
}

- (void)_showSelectionViewOnIconView:(SBIconView *)iconView
{
    if (_currentSelectionView) {
        return;
    }

    _currentSelectionView = [[STKSelectionView alloc] initWithIconView:iconView
        inLayout:_iconViewsLayout
        position:[self _locationMaskForIcon:_centralIcon]
        centralIconView:[self _iconViewForIcon:_centralIcon]
        displacedIcons:_displacedIconsLayout];

    _currentSelectionView.delegate = self;
    [_iconViewsLayout getPosition:&_selectionViewPosition andIndex:&_selectionViewIndex forIcon:iconView];

    _currentSelectionView.alpha = 0.f;
    [[_iconController contentView] addSubview:_currentSelectionView];
    [_currentSelectionView layoutSubviews];

    [_currentSelectionView scrollToDefaultAnimated:NO];

    [_iconController scrollView].scrollEnabled = NO;

    [UIView animateWithDuration:kAnimationDuration animations:^{
        [_currentSelectionView prepareForDisplay];
        _currentSelectionView.alpha = 1.f;

        [STKListViewForIcon(_centralIcon) makeIconViewsPerformBlock:^(SBIconView *iv) { 
            if (iv != [self _iconViewForIcon:_centralIcon]){
                iv.alpha = 0.f; 
            }
        }];
        [_iconController dock].superview.alpha = 0.f;
    }];
}

- (void)_hideActiveSelectionView
{
    if (!_currentSelectionView || _isClosingSelectionView) {
        return;
    }

    _isClosingSelectionView = YES;

    [UIView animateWithDuration:kAnimationDuration animations:^{
        // Set the alphas back to normal
        [STKListViewForIcon(_centralIcon) makeIconViewsPerformBlock:^(SBIconView *iv) { 
            if ((iv != [self _iconViewForIcon:_centralIcon]) && !([[_iconsHiddenForPlaceHolders allIcons] containsObject:iv.icon]) && !([[_offScreenIconsLayout allIcons] containsObject:iv.icon])) {
                iv.alpha = 1.f; 
            }
        }];
        [_iconController dock].superview.alpha = 1.f;

        SBIcon *selectedIcon = [[_currentSelectionView highlightedIcon] retain];
        [self _addIcon:selectedIcon atIndex:(_isEmpty ? 0 : _selectionViewIndex) position:_selectionViewPosition];
        [selectedIcon release];

        [_currentSelectionView prepareForRemoval];
        _currentSelectionView.alpha = 0.f;

        MAP([_offScreenIconsLayout allIcons], ^(SBIcon *icon) {
            // _offScreenIconsLayout is all new at this point
            [self _iconViewForIcon:icon].alpha = 0.f;
        });
        
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
    [self _hideActiveSelectionView];
}

- (void)_addIcon:(SBIcon *)iconToAdd atIndex:(NSUInteger)idx position:(STKLayoutPosition)addPosition
{
    SBIcon *removedIcon = nil;
    if (_isEmpty) {
        if (iconToAdd.isPlaceholder || !(idx < [_iconViewsLayout iconsForPosition:addPosition].count)) {
            return;
        }    

        SBIconView *iconView = [_iconViewsLayout iconsForPosition:addPosition][idx];
        [iconView setIcon:iconToAdd]; // Convert the placeholder icon into a regular app icon. SBIconView <3
        
        [_appearingIconsLayout removeAllIcons];
        [_appearingIconsLayout release];
        _appearingIconsLayout = [[STKIconLayout alloc] init];
        [_appearingIconsLayout addIcon:iconToAdd toIconsAtPosition:addPosition];

        [self _setAlpha:1.f forLabelAndShadowOfIconView:iconView];

        _isEmpty = NO;
        _hasPlaceHolders = YES; // We already have these, courtesy all the empty icons in the stack. :P
        self.isEditing = YES;
    } 
    else {  // isEmpty == NO
        NSArray *iconViews = [_iconViewsLayout iconsForPosition:addPosition];
        if (idx <= (iconViews.count - 1)) {
            SBIconView *iconViewToChange = iconViews[idx];
            BOOL iconToChangeWasPlaceholder = iconViewToChange.icon.isPlaceholder;
            if ((iconToChangeWasPlaceholder && iconToAdd.isPlaceholder) || [iconViewToChange.icon.leafIdentifier isEqualToString:iconToAdd.leafIdentifier]) {
                // If both icons are the same, simply exit.
                // It is better to simply check a BOOL instead of comparing strings, which is why the placeholder check is first
                return;
            }

            if (!iconToChangeWasPlaceholder) {
                removedIcon = [iconViewToChange.icon retain];
            }

            // Set the icon!
            [iconViewToChange setIcon:iconToAdd];

            SBIconView *centralView = [self _iconViewForIcon:_centralIcon];
            [centralView bringSubviewToFront:centralView.iconImageView];
            [centralView sendSubviewToBack:iconViews[idx]];

            if (iconToAdd.isPlaceholder) {
                // Remove the icon that is to be replaced with a placeholder from _appearingIcons
                [_appearingIconsLayout removeIconAtIndex:idx fromIconsAtPosition:addPosition];
                [self _setAlpha:0.f forLabelAndShadowOfIconView:iconViewToChange];

                // Setting this makes the icon view be removed as a part of the placeholder removal routine.
                _hasPlaceHolders = YES;

                UIImageView *overlay = objc_getAssociatedObject(iconViewToChange, @selector(overlayView));
                [overlay removeFromSuperview];
                [overlay release];

                objc_setAssociatedObject(iconViewToChange, @selector(overlayView), nil, OBJC_ASSOCIATION_ASSIGN);
            }
            else {
                [_appearingIconsLayout setIcon:iconToAdd atIndex:idx position:addPosition];
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

            // If _appearingIconsLayout has count 0, we've removed all non-placeholders from it in the if (iconToAdd.isPlaceholder) check
            _isEmpty = ([_appearingIconsLayout totalIconCount] == 0);            
            if (_isEmpty) {
                // We are definitely not editing now, since the stack has switched over to imitate an empty stack
                _isEditing = NO;
                _hasPlaceHolders = NO;

                [_closingAnimationOpQueue stk_addOperationToRunOnMainThreadWithBlock:^{
                    for (SBIcon *icon in [_iconsHiddenForPlaceHolders allIcons]) {
                        [self _iconViewForIcon:icon].alpha = 1.f;
                    }
                    [self _iconViewForIcon:_centralIcon].transform = CGAffineTransformMakeScale(1.f, 1.f);
                }];

                [_postCloseOpQueue stk_addOperationToRunOnMainThreadWithBlock:^{
                    MAP([_iconsHiddenForPlaceHolders allIcons], ^(SBIcon *icon) {
                        [self _iconViewForIcon:icon].alpha = 1.f;
                    });
                }];
            }
        }
    }

    BOOL needsToHide = (!iconToAdd.isPlaceholder && [[_iconController model] isIconVisible:iconToAdd]);

    if (_interactionHandler) {
        _interactionHandler(self, nil, YES, (iconToAdd.isPlaceholder ? nil : iconToAdd));
    }

    // After the interaction handler has processed it, it should be out of the prefs. If it is still to go into a stack...bleh.
    BOOL needsToShow = (removedIcon && !(ICON_IS_IN_STACK(removedIcon)));

    if (removedIcon && ICON_IS_IN_STACK(removedIcon)) {
        // If the icon was removed, but it's come back, don't do anything, geddit?
        removedIcon = nil;
    }

    if (!_hasLayoutOp) {
        if (!_iconsToHideOnClose) {
            _iconsToHideOnClose = [NSMutableArray new];
        }
        if (!_iconsToShowOnClose) {
            _iconsToShowOnClose = [NSMutableArray new];
        }

        _hasLayoutOp = YES;

        STKIdentifiedOperation *op = [STKIdentifiedOperation operationWithBlock:^{
            SBIconModel *model = [_iconController model];
            [model _postIconVisibilityChangedNotificationShowing:_iconsToShowOnClose hiding:_iconsToHideOnClose];
            [[NSNotificationCenter defaultCenter] postNotificationName:STKRecalculateLayoutsNotification object:nil userInfo:nil];

            [_iconsToHideOnClose release];
            _iconsToHideOnClose = nil;

            [_iconsToShowOnClose release];
            _iconsToShowOnClose = nil;

            _hasLayoutOp = NO;

        } identifier:kSTKIconModelLayoutOpID queue:dispatch_get_main_queue()];

        [_postCloseOpQueue addOperation:op];
    }

    if (needsToHide) {
        [_iconsToHideOnClose addObject:iconToAdd];
    }
    if (needsToShow) {
        [_iconsToShowOnClose addObject:removedIcon];
    }

    [removedIcon release];
}

- (SBIcon *)_displacedIconAtPosition:(STKLayoutPosition)position intersectingAppearingIconView:(SBIconView *)iconView
{
    for (SBIcon *dispIcon in [_displacedIconsLayout iconsForPosition:position]) {
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

- (void)icon:(id)arg1 touchMovedWithEvent:(id)arg2
{
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

    if (![iconView.icon.leafIdentifier isEqual:_centralIcon.leafIdentifier] && (_isEditing || [iconView.icon.leafIdentifier isEqualToString:STKPlaceHolderIconIdentifier])) {
        [self _showSelectionViewOnIconView:iconView];
        return;
    }

    [iconView setHighlighted:YES delayUnhighlight:YES];
    if (_interactionHandler) {
        _interactionHandler(self, iconView, NO, nil);
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

- (BOOL)iconAllowJitter:(SBIconView *)iconView
{
    return YES;
}

@end
