#import "STKStackManager.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "substrate.h"

#import <objc/runtime.h>

#import <SpringBoard/SpringBoard.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

#import "SBIconViewMap+AcervosSafety.h"


// Keys to be used for persistence dict
NSString * const STKStackManagerCentralIconKey = @"STKCentralIcon";
NSString * const STKStackManagerStackIconsKey  = @"STKStackIcons";

NSString * const STKRecalculateLayoutsNotification = @"STKRecalculate";



#define kMaximumDisplacement kEnablingThreshold + 40
#define kAnimationDuration   0.2
#define kDisabledIconAlpha   0.2
#define kBandingAllowance    ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) ? 25 : 50)
#define kGhostlyRequesterID  1
#define kOverlayDuration     0.12
#define kPopoutDistance      9


#pragma mark - Private Method Declarations
@interface STKStackManager ()
{
    SBIcon                   *_centralIcon;
    STKIconLayout            *_appearingIconsLayout;
    STKIconLayout            *_displacedIconsLayout;
    STKIconLayout            *_iconViewsLayout;
    STKInteractionHandler     _interactionHandler;

    CGFloat                   _distanceRatio;
    CGFloat                   _popoutCompensationRatio;
    STKIconLayout            *_offScreenIconsLayout;

    CGFloat                   _lastDistanceFromCenter;
    BOOL                      _hasPreparedGhostlyIcons;
    BOOL                      _hasOffScreenIcons;
    BOOL                      _needsLayout;

    UISwipeGestureRecognizer *_swipeRecognizer;
    UITapGestureRecognizer   *_tapRecognizer;

    id<SBIconViewDelegate>    _previousDelegate;

    STKIconLayout            *_placeHolderViewsLayout;
    STKIconLayout            *_iconsHiddenForPlaceHolders;

    SBIconController         *_iconController;
}

/*
*   Icon moving
*/
- (void)_animateToOpenPositionWithDuration:(NSTimeInterval)duration;
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock duration:(NSTimeInterval)duration animateCentralIcon:(BOOL)animateCentralIcon keepGhosting:(BOOL)shouldKeepGhostedIcons;

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance;

/*
*   Gesture Recognizing
*/
- (void)_setupGestureRecognizers;
- (void)_handleCloseGesture:(UISwipeGestureRecognizer *)sender; // this is the default action for both swipes
- (void)_cleanupGestureRecognizers;

- (SBIconView *)_iconViewForIcon:(SBIcon *)icon;
- (STKPositionMask)_locationMaskForIcon:(SBIcon *)icon;

- (void)_relayoutRequested:(NSNotification *)notif;

// Returns the target origin for icons in the stack at the moment, in _centralIcon's iconView. To use with the list view, use -[UIView convertPoint:toView:]
- (CGPoint)_targetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance;

// Manually calculates where the displaced icons should go.
- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position usingLayout:(STKIconLayout *)layout;
- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position;

- (void)_calculateDistanceRatio;
- (void)_findIconsWithOffScreenTargets;

/*
*   Alpha
*/
// This sexy method disables/enables icon interaction as required.
- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral; 

// Applies it to the shadow and label of the appearing icons
- (void)_setAlphaForAppearingLabelsAndShadows:(CGFloat)alpha;

- (void)_setPageControlAlpha:(CGFloat)alpha;

/*
*   Editing Handling
*/
- (void)_drawOverlayOnAllIcons;
- (void)_removeOverlays;
- (void)_insertAddButtonsInEmptyLocations;
- (void)_removePlaceHolders;
- (void)_placeHolderTapped:(UITapGestureRecognizer *)tapRecognizer;

- (void)__animateOpen;
- (void)__animateClosed;

    @end


@implementation STKStackManager 

// Make the property use this ivar
@synthesize currentIconDistance = _lastDistanceFromCenter;

static BOOL __isStackOpen;
static BOOL __stackInMotion;

+ (BOOL)anyStackOpen
{
    return __isStackOpen;
}

+ (BOOL)anyStackInMotion
{
    return __stackInMotion;
}

+ (NSString *)layoutsPath
{
    return [NSHomeDirectory() stringByAppendingFormat:@"/Library/Preferences/%@/Layouts", kSTKTweakName];
}


#pragma mark - Public Methods
- (instancetype)initWithContentsOfFile:(NSString *)file
{
    _iconController = [objc_getClass("SBIconController") sharedInstance];
    SBIconModel *model = [(SBIconController *)_iconController model];

    NSDictionary *attributes = [NSDictionary dictionaryWithContentsOfFile:file];

    NSMutableArray *stackIcons = [NSMutableArray arrayWithCapacity:(((NSArray *)attributes[STKStackManagerStackIconsKey]).count)];
    for (NSString *identifier in attributes[STKStackManagerStackIconsKey]) {
        // Get the SBIcon instances for the identifiers
        SBIcon *icon = [model expectedIconForDisplayIdentifier:identifier];
        if (icon) {
            [stackIcons addObject:[model expectedIconForDisplayIdentifier:identifier]];
        }
        else {
            CLog(@"Couldn't get icon for identifier %@. Confirm that the ID is correct and the app is installed.", identifier);
        }
    }

    SBIcon *centralIcon = [model expectedIconForDisplayIdentifier:attributes[STKStackManagerCentralIconKey]];
    if (!centralIcon) {
        CLog(@"Central Icon: %@ doesn't exist, dying quietly...", attributes[STKStackManagerCentralIconKey]);
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

        if (!icons) {
            _appearingIconsLayout = [[STKIconLayoutHandler emptyLayoutForIconAtPosition:mask] retain];
            _isEmpty = YES;
        }
        else {
            _appearingIconsLayout = [[STKIconLayoutHandler layoutForIcons:icons aroundIconAtPosition:mask] retain];
        }

        _displacedIconsLayout = [[STKIconLayoutHandler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconsLayout] retain];

        [icons release];

        [self _calculateDistanceRatio];
        [self _findIconsWithOffScreenTargets];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_relayoutRequested:) name:STKRecalculateLayoutsNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(__animateOpen) name:[NSString stringWithFormat:@"OpenSesame %@", _centralIcon.leafIdentifier] object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(__animateClosed) name:[NSString stringWithFormat:@"CloseSesame %@", _centralIcon.leafIdentifier] object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [self cleanupView];

    SBIconListView *listView = STKListViewForIcon(_centralIcon);
    [listView setIconsNeedLayout];
    [listView layoutIconsIfNeeded:kAnimationDuration domino:NO];

    [self _setGhostlyAlphaForAllIcons:1.f excludingCentralIcon:NO];

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
    @synchronized(self) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:[STKStackManager layoutsPath]]) {
            // Check if the directory exists in the first place
            [[NSFileManager defaultManager] createDirectoryAtPath:[STKStackManager layoutsPath] withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions : @511} error:NULL];
        }

        NSDictionary *fileDict = @{ STKStackManagerCentralIconKey : _centralIcon.leafIdentifier,
                                    STKStackManagerStackIconsKey  : [[_appearingIconsLayout allIcons] valueForKeyPath:@"leafIdentifier"] };
        [fileDict writeToFile:file atomically:YES];
    }
}

- (void)recalculateLayouts
{
    SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
    if (centralIconView.location != SBIconViewLocationHomeScreen) {
        // I KNOW THERE'S A HOOK INTO -iconViewDidChangeLocation: that will pick this up. 
        // THE SHIT I WRITE...
        [[objc_getClass("SBIconViewMap") homescreenMap] iconViewDidChangeLocation:centralIconView];
        return;
    }

    NSArray *stackIcons = [_appearingIconsLayout allIcons];

    [_appearingIconsLayout release];
    [_displacedIconsLayout release];

    if (_isEmpty) {
        _appearingIconsLayout = [[STKIconLayoutHandler emptyLayoutForIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
    }
    else {
        _appearingIconsLayout = [[STKIconLayoutHandler layoutForIcons:stackIcons aroundIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
    }

    _displacedIconsLayout = [[STKIconLayoutHandler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconsLayout] retain];

    [self _calculateDistanceRatio];
    [self _findIconsWithOffScreenTargets];

    if (_hasSetup) {
        [self cleanupView];
        [self setupPreview];
    }
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
        
        [iconView setIcon:icon];
        [iconView setDelegate:self];

        iconView.frame = centralIconView.bounds;
        iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);
        [iconView setIconLabelAlpha:0.f];
        [[iconView valueForKeyPath:@"_shadow"] setAlpha:0.f];

        [_iconViewsLayout addIcon:iconView toIconsAtPosition:position];

        [centralIconView insertSubview:iconView atIndex:0];
        iconView.userInteractionEnabled = NO;

        for (UIGestureRecognizer *recognizer in iconView.gestureRecognizers) {
            [iconView removeGestureRecognizer:recognizer];
        }
    }];

    [centralIconView bringSubviewToFront:centralIconView.iconImageView];

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

    [_iconViewsLayout release];
    _iconViewsLayout = nil;

    _hasSetup = NO;
}

#pragma mark - Preview Handling
- (void)setupPreview
{
    [self setupViewIfNecessary];

    /*
    *   BULLSHIT CODE BEGINS
    */
    CGFloat popoutDistance = (_isEmpty ? 0 : kPopoutDistance);
    [_iconViewsLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
        CGRect frame = [self _iconViewForIcon:_centralIcon].bounds;
        CGPoint newOrigin = frame.origin;

        // Check if it's the last object
        if (idx == currentArray.count - 1) {
            iconView.alpha = 1.f;

            // This is probably how the rest of the code should've been written
            CGFloat *memberToModify = ((position == STKLayoutPositionTop || position == STKLayoutPositionBottom) ? &newOrigin.y : &newOrigin.x);

            // the member to modify needs to be subtracted from in case of t/l.
            CGFloat negator = (position == STKLayoutPositionTop || position == STKLayoutPositionLeft ? -1 : 1);

            *memberToModify += popoutDistance * negator;
        }
        else {
            // Only the last icon at a particular side needs to be shown
            iconView.alpha = 0.f;
        }

        frame.origin = newOrigin; 
        iconView.frame = frame;

        // Scale the icon back down to the smaller size.
        iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);

        // Hide the labels and shadows
        ((UIImageView *)[iconView valueForKey:@"_shadow"]).alpha = 0.f;
        [iconView setIconLabelAlpha:0.f];
        iconView.userInteractionEnabled = NO;
    }];
    /*
    *   BULLSHIT CODE ENDS
    */
}

#pragma mark - Moving Icons
- (void)touchesDraggedForDistance:(CGFloat)distance
{
    if (_isExpanded && ![[_iconController scrollView] isDragging]) {
        return;
    }

    if (_needsLayout) {
        [self recalculateLayouts];
        _needsLayout = NO;
    }

    if (!_hasSetup) {
        [self setupPreview];
    }
    
    if (!_hasPreparedGhostlyIcons) {
        [_iconController prepareToGhostCurrentPageIconsForRequester:kGhostlyRequesterID skipIcon:_centralIcon];
        _hasPreparedGhostlyIcons = YES;
    }
    __stackInMotion = YES;

    [self _moveAllIconsInRespectiveDirectionsByDistance:distance];
    
    if (!_hasOffScreenIcons) {
        [self _findIconsWithOffScreenTargets];
        _hasOffScreenIcons = YES;
    }

    CGFloat alpha = STKAlphaFromDistance(_lastDistanceFromCenter);
    [self _setGhostlyAlphaForAllIcons:alpha excludingCentralIcon:YES];
    [self _setPageControlAlpha:alpha];
    if (!_isEmpty) {
        [self _setAlphaForAppearingLabelsAndShadows:(1 - alpha)];
    }

    
    CGFloat midWayDistance = STKGetCurrentTargetDistance() / 2.0;
    if (_lastDistanceFromCenter <= midWayDistance) {
        // If the icons are past the halfway mark, start increasing/decreasing their scale.
        // This looks beatuiful. Yay me.
        CGFloat stackIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kStackPreviewIconScale);
        MAP([_iconViewsLayout allIcons], ^(SBIconView *iconView) {
            iconView.iconImageView.transform = CGAffineTransformMakeScale(stackIconTransformScale, stackIconTransformScale);
        });

        CGFloat centralIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kCentralIconPreviewScale);
        [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(centralIconTransformScale, centralIconTransformScale);
    }
    else {
        [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
        MAP([_iconViewsLayout allIcons], ^(SBIconView *iconView) { iconView.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f); });        
    }

    __stackInMotion = NO;
}

- (void)touchesEnded
{
    if (_lastDistanceFromCenter >= kEnablingThreshold && !_isExpanded) {
        // Set this now, not waiting for the animation to complete, so anyone asking questions gets the right answer... LOL
        _isExpanded = YES;
        __isStackOpen = YES;

        [self openStack];
    }
    else {
        [self _animateToClosedPositionWithCompletionBlock:^{
            if (_interactionHandler) {
                _interactionHandler(nil);
            }
        } duration:kAnimationDuration animateCentralIcon:NO keepGhosting:NO];
    }
}
 
- (void)closeStackWithCompletionHandler:(void(^)(void))completionHandler
{
    [self _animateToClosedPositionWithCompletionBlock:^{
        if (completionHandler) {
            completionHandler();
        }
    } duration:kAnimationDuration animateCentralIcon:YES keepGhosting:NO];
}

- (void)closeForSwitcher
{
    if (!_isExpanded) {
        [self _animateToClosedPositionWithCompletionBlock:nil duration:kAnimationDuration animateCentralIcon:NO keepGhosting:YES];
    }
}

- (void)openStack
{
    [self _animateToOpenPositionWithDuration:kAnimationDuration];
}

- (void)closeStack
{
    [self closeStackWithCompletionHandler:nil];
}


#pragma mark - Setter/Getter Overrides
- (void)setIsEditing:(BOOL)isEditing
{
    if (_isEmpty) {
        return;
    }

    _isEditing = isEditing;

    if (_isEditing) {
        [self _drawOverlayOnAllIcons];
        [self _insertAddButtonsInEmptyLocations];
    }
    else {
        [self _removeOverlays];
        [self _removePlaceHolders];
    }
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
    SBIconView *touchedIconView = nil;
    CGRect centralIconViewFrame = [self _iconViewForIcon:_centralIcon].bounds;
    
    if (CGRectContainsPoint(centralIconViewFrame, point)) {
        return [self _iconViewForIcon:_centralIcon];
    } 

    for (SBIconView *iconView in [_iconViewsLayout allIcons]) {
        if (CGRectContainsPoint(iconView.frame, point)) {
            touchedIconView = iconView;
        }
    }
    return touchedIconView;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#pragma mark - Open Animation
- (void)_animateToOpenPositionWithDuration:(NSTimeInterval)duration;
{
    if (!_hasSetup) {
        [self setupPreview];
    }

    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);

        [_iconViewsLayout enumerateIconsUsingBlockWithIndexes:^(SBIconView *iconView, STKLayoutPosition position, NSArray *currentArray, NSUInteger idx) {
            CGRect newFrame = iconView.frame;
            
            newFrame.origin = [self _targetOriginForIconAtPosition:position distanceFromCentre:idx + 1];
            iconView.frame = newFrame;
            iconView.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
            
            iconView.delegate = self;
            iconView.userInteractionEnabled = YES;

            if (!_isEmpty) {
                iconView.iconLabelAlpha = 1.f;

                ((UIImageView *)[iconView valueForKey:@"_shadow"]).alpha = 1.f;
                ((UIView *)[iconView valueForKey:@"_accessoryView"]).alpha = 1.f;
            }
        }];

        [_displacedIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
            SBIconView *iconView = [self _iconViewForIcon:icon];
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _displacedOriginForIcon:icon withPosition:position];
            iconView.frame = newFrame;
        }];

        [self _setPageControlAlpha:0];
        [self _setGhostlyAlphaForAllIcons:0.f excludingCentralIcon:YES];

        [_offScreenIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition pos) {
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
            __isStackOpen = YES;
        }
    }];
}

#pragma mark - Close Animation
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock duration:(NSTimeInterval)duration animateCentralIcon:(BOOL)animateCentralIcon keepGhosting:(BOOL)shouldKeepGhostedIcons
{
    UIView *centralView = [[self _iconViewForIcon:_centralIcon] iconImageView];
    CGFloat scale = (_isEmpty ? 1.f : kCentralIconPreviewScale);

    [UIView animateWithDuration:(duration / 2.0) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        // Animate central imageview shrink/grow
        if (animateCentralIcon) {
            centralView.transform = CGAffineTransformMakeScale(scale - 0.1f, scale - 0.1f);
        }
    } completion:^(BOOL finished) {
        if (finished) {
            // Animate it back to `scale`
            [UIView animateWithDuration:(duration / 2.0) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                centralView.transform = CGAffineTransformMakeScale(scale, scale);
            } completion:nil];
        }
    }];
    
    // Make sure we're not in the editing state
    self.isEditing = NO;

    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        [self setupPreview];

        // Set the alphas back to original
        [self _setGhostlyAlphaForAllIcons:0.999f excludingCentralIcon:YES];
        [self _setPageControlAlpha:1];

        // Bring the off screen icons back to life! :D
        [_offScreenIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition pos) {
            [self _iconViewForIcon:icon].alpha = 1.f;
        }];
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
            _hasPreparedGhostlyIcons = NO;

            [_offScreenIconsLayout release];
            _offScreenIconsLayout = nil;
            _hasOffScreenIcons = NO;

            if (_isEmpty) {
                // We can remove the place holder icon views if the stack is empty. No need to have 4 icon views hidden behind every damn icon.
                [self cleanupView];
            }
            
            _isExpanded = NO;
            __isStackOpen = NO;

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

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance
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

        if (iconView.alpha != 1.f) {
            iconView.alpha = 1.f;
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

            if (idx == 0) {
                _lastDistanceFromCenter = fabsf(iconView.frame.origin.y - centralFrame.origin.y);
            }
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
        CGFloat popComp = (((idx == currentArray.count - 1) && !(_isEmpty)) ? ((*targetCoord - kPopoutDistance * negator) / *targetCoord) : 1.f);

        moveDistance *= (multFactor * popComp);


        if (IS_GREATER((*currentCoord + (moveDistance / popComp)), *targetCoord, position)) {
            // Don't compensate for anything if the icon is moving past the target
            moveDistance /= popComp;
            moveDistance /= distanceRatio;
        }

        // Modify the target to allow for a `kBandingAllowance` distance extra for the rubber banding effect
        *targetCoord += (kBandingAllowance * negator);

        if (IS_LESSER((*currentCoord + moveDistance), *targetCoord, position)) {
            *newCoord += moveDistance;
        }
        else if (IS_GREATER((*currentCoord + moveDistance), *targetCoord, position)) {
            *newCoord = *targetCoord;
        }
        else if (IS_LESSER((*currentCoord + moveDistance), *centralCoord, position)) {
            *newCoord = *centralCoord;
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

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
    if (recognizer == _tapRecognizer) {
        // The tap recogniser shouldn't receive a touch if it's on a stacked icon
        if ([[self _iconViewForIcon:_centralIcon] pointInside:[touch locationInView:[self _iconViewForIcon:_centralIcon]] withEvent:nil]) {
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
    if (self.isEditing && [sender isKindOfClass:[UITapGestureRecognizer class]]) {
        self.isEditing = NO;
        return;
    }

    [self _cleanupGestureRecognizers];
    [self closeStackWithCompletionHandler:^{ if (_interactionHandler) _interactionHandler(nil); }];
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
    _popoutCompensationRatio = (_isEmpty ? 1.f : (verticalDistance / (verticalDistance - kPopoutDistance))); // This is the ratio of the target distance of a stack icon to a displaced icon, respectively
}

- (void)_findIconsWithOffScreenTargets
{
    [_offScreenIconsLayout release];
    _offScreenIconsLayout = [[STKIconLayout alloc] init]; 


    [_displacedIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        CGRect listViewBounds = STKListViewForIcon(_centralIcon).bounds;

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

- (void)_setAlphaForAppearingLabelsAndShadows:(CGFloat)alpha
{
    for (SBIconView *iconView in [_iconViewsLayout allIcons]) {
        ((UIImageView *)[iconView valueForKey:@"_shadow"]).alpha = alpha;
        [iconView setIconLabelAlpha:alpha];
        ((UIView *)[iconView valueForKey:@"_accessoryView"]).alpha = alpha;
    }
}

- (void)_setPageControlAlpha:(CGFloat)alpha
{
    [_iconController setPageControlAlpha:alpha];
}


#pragma mark - Editing Handling
- (void)_drawOverlayOnAllIcons
{
    void(^addOverlayToView)(SBIconView *) = ^(SBIconView *iconView) {
        UIImageView *imageView = [[[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:PATH_TO_IMAGE(@"EditingOverlay")]] autorelease];
        imageView.center = (CGPoint){CGRectGetMidX(iconView.iconImageView.frame), CGRectGetMidY(iconView.iconImageView.frame) + 2};

        [UIView animateWithDuration:kOverlayDuration animations:^{
            imageView.alpha = 0.f;
            [iconView.iconImageView addSubview:imageView];
            imageView.alpha = 1.f;
        }];

        objc_setAssociatedObject(iconView, @selector(overlayView), imageView, OBJC_ASSOCIATION_ASSIGN);
    };

    MAP([_iconViewsLayout allIcons], addOverlayToView);
    addOverlayToView([self _iconViewForIcon:_centralIcon]);
}

- (void)_removeOverlays
{
    void (^removeOverlayFromView)(SBIconView *) = ^(SBIconView *iconView) {
        UIImageView *overlayView = objc_getAssociatedObject(iconView, @selector(overlayView));

        [UIView animateWithDuration:kOverlayDuration animations:^{
            overlayView.alpha = 0.f;
        } completion:^(BOOL finished) {
            if (finished) {
                [overlayView removeFromSuperview];
            }
        }];

        objc_setAssociatedObject(iconView, @selector(overlayView), nil, OBJC_ASSOCIATION_ASSIGN);
    };

    MAP([_iconViewsLayout allIcons], removeOverlayFromView);
    removeOverlayFromView([self _iconViewForIcon:_centralIcon]);
}

- (void)_insertAddButtonsInEmptyLocations
{
    STKIconLayout *placeHolderLayout = [STKIconLayoutHandler layoutForPlaceHoldersInLayout:_appearingIconsLayout withPosition:[self _locationMaskForIcon:_centralIcon] placeHolderClass:[NSObject class]];
    
    SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];

    [placeHolderLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        UIImageView *imageView = [[[UIImageView alloc] initWithImage:UIIMAGE_NAMED(@"EditingOverlay")] autorelease];

        CGPoint newOrigin = [centralIconView convertPoint:[self _targetOriginForIconAtPosition:position distanceFromCentre:[_appearingIconsLayout iconsForPosition:position].count + index + 1]
                                                   toView:STKListViewForIcon(_centralIcon)];
        newOrigin.x -= 2;
        newOrigin.y -= 2;
        imageView.frame = (CGRect){newOrigin, imageView.frame.size};

        if (!_placeHolderViewsLayout) {
            _placeHolderViewsLayout = [[STKIconLayout alloc] init];
        }
        
        [_placeHolderViewsLayout addIcon:imageView toIconsAtPosition:position];

        if (!_iconsHiddenForPlaceHolders) {
            _iconsHiddenForPlaceHolders = [[STKIconLayout alloc] init];
        }


        MAP([_displacedIconsLayout iconsForPosition:position], ^(SBIcon *icon) {
            if (CGRectIntersectsRect([self _iconViewForIcon:icon].frame, (CGRect){{newOrigin.x + 2, newOrigin.y + 2}, imageView.frame.size})) {
                [_iconsHiddenForPlaceHolders addIcon:icon toIconsAtPosition:position];
            }
        });

        UITapGestureRecognizer *recognizer = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_placeHolderTapped:)] autorelease];
        recognizer.numberOfTapsRequired = 1;
        recognizer.numberOfTouchesRequired = 1;

        [_tapRecognizer requireGestureRecognizerToFail:recognizer];
        [imageView addGestureRecognizer:recognizer];
        imageView.userInteractionEnabled = YES;

        [UIView animateWithDuration:kOverlayDuration animations:^{
            imageView.alpha = 0.f;
            [centralIconView.superview addSubview:imageView];
            imageView.alpha = 1.f;
        }];
    }];

    MAP([_iconsHiddenForPlaceHolders allIcons], ^(SBIcon *icon){ [self _iconViewForIcon:icon].alpha = 0.f; });
}

- (void)_removePlaceHolders
{
    MAP([_iconsHiddenForPlaceHolders allIcons], ^(SBIcon *icon){ [self _iconViewForIcon:icon].alpha = 1.f; });
   
    MAP([_placeHolderViewsLayout allIcons], ^(UIView *view) {
        [UIView animateWithDuration:kOverlayDuration animations:^{
            view.alpha = 0.f;
        } completion:^(BOOL finished) {
            if (finished) {
                [view removeFromSuperview];
            }
        }];
    });


    [_iconsHiddenForPlaceHolders release];
    _iconsHiddenForPlaceHolders = nil;
    
    [_placeHolderViewsLayout release];
    _placeHolderViewsLayout = nil;
}

- (void)_placeHolderTapped:(UITapGestureRecognizer *)tapRecognizer
{

}

#pragma mark - Demo
- (void)__animateOpen
{
    [self _animateToOpenPositionWithDuration:0.5];
}

- (void)__animateClosed
{
    [self _animateToClosedPositionWithCompletionBlock:nil duration:0.5 animateCentralIcon:YES keepGhosting:NO];
}

#pragma mark - SBIconViewDelegate
- (void)iconTouchBegan:(SBIconView *)iconView
{
    [iconView setHighlighted:YES];
}

- (void)icon:(SBIconView *)iconView touchEnded:(BOOL)arg2
{
    [iconView setHighlighted:NO];
}

- (void)iconTapped:(SBIconView *)iconView
{
    if (_isEditing) {
        return;
    }

    if ([iconView.icon.leafIdentifier isEqualToString:STKPlaceHolderIconIdentifier]) {
        // FINISH ME
        return;
    }

    [iconView setHighlighted:YES delayUnhighlight:YES];
    if (_interactionHandler) {
        _interactionHandler(iconView);
    }
}

- (void)icon:(id)arg1 touchMovedWithEvent:(id)arg2
{
    
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    [iconView setHighlighted:NO];
    self.isEditing = !(self.isEditing);
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return ([_iconController hasOpenFolder] ? NO : YES);
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
