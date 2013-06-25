#import "STKStackManager.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "substrate.h"

#import <objc/runtime.h>

#import <SpringBoard/SpringBoard.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

// Keys to be used for persistence dict
NSString * const STKStackManagerCentralIconKey = @"STKCentralIcon";
NSString * const STKStackManagerStackIconsKey  = @"STKStackIcons";


// keys for use in map table
static NSString * const STKStackTopIconsKey    = @"topicons";
static NSString * const STKStackBottomIconsKey = @"bottomicons";
static NSString * const STKStackLeftIconsKey   = @"lefticons";
static NSString * const STKStackRightIconsKey  = @"righticons";

#define kMaximumDisplacement kEnablingThreshold + 40
#define kAnimationDuration   0.2
#define kDisabledIconAlpha   0.2
#define kBandingAllowance    ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) ? 25 : 50)
#define kGhostlyRequesterID  23
#define kOverlayDuration     0.12


#pragma mark - Private Method Declarations
@interface STKStackManager ()
{
    SBIcon                   *_centralIcon;
    STKIconLayout            *_appearingIconsLayout;
    STKIconLayout            *_displacedIconsLayout;
    NSMapTable               *_iconViewsTable;
    STKInteractionHandler     _interactionHandler;

    CGFloat                   _distanceRatio;
    STKIconLayout            *_offScreenIconsLayout;

    CGFloat                   _lastDistanceFromCenter;
    BOOL                      _hasPreparedGhostlyIcons;

    UISwipeGestureRecognizer *_swipeRecognizer;
    UITapGestureRecognizer   *_tapRecognizer;

    id<SBIconViewDelegate>    _previousDelegate;

    STKIconLayout            *_placeHolderViewsLayout;
    STKIconLayout            *_iconsHiddenForPlaceHolders;
}

/*
*   Icon moving
*/
- (void)_animateToOpenPositionWithDuration:(NSTimeInterval)duration;
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock duration:(NSTimeInterval)duration animateCentralIcon:(BOOL)animateCentralIcon;

- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance;

/*
*   Gesture Recognizing
*/
- (void)_setupGestureRecognizers;
- (void)_handleCloseGesture:(UISwipeGestureRecognizer *)sender; // this is the default action for both swipe
- (void)_cleanupGestureRecognizers;

- (SBIconView *)_iconViewForIcon:(SBIcon *)icon;
- (STKPositionMask)_locationMaskForIcon:(SBIcon *)icon;

// Returns the target origin for icons in the stack at the moment.
// Returns the target origin for icons in the stack at the moment, in _centralIcon's iconView. To use with the list view, use -[UIView convertPoint:toView:]
- (CGPoint)_targetOriginForIconAtPosition:(STKLayoutPosition)position distanceFromCentre:(NSInteger)distance;

// Manually calculates where the displaced icons should go.
- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position usingLayout:(STKIconLayout *)layout;
- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position;

// Returns the distance of a point from the central icon's centre, calculated using distance formula
- (CGFloat)_distanceFromCentre:(CGPoint)centre;

- (void)_makeAllIconsPerformBlock:(void(^)(SBIcon *))block; // Includes icons in dock

- (id)_keyForPosition:(STKLayoutPosition)position;
- (NSArray *)_appearingIconsForPosition:(STKLayoutPosition)position;
- (NSArray *)_appearingIconViewsForPosition:(STKLayoutPosition)position;
- (NSArray *)_allAppearingIconViews;

- (void)_calculateDistanceRatio;
- (void)_findIconsWithOffScreenTargets;

/*
*   Alpha
*/
- (void)_setAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)shouldExcludeCentral disableInteraction:(BOOL)disableInteraction;

// This sexy method disables/enables icon interaction as required.
- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral; 

// Applies it to the shadow and label of the appearing icons
- (void)_setAlphaForAppearingLabelsAndShadows:(CGFloat)alpha;

- (void)_setInteractionEnabled:(BOOL)enabled forAllIconsExcludingCentral:(BOOL)excludeCentral;
- (void)_setPageControlAlpha:(CGFloat)alpha;

/*
*   Notifications!
*/ 
- (void)_editingStateChanged:(NSNotification *)notification;

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
    CLog(@"Initialising from file: %@", file);
    SBIconModel *model = [(SBIconController *)[objc_getClass("SBIconController") sharedInstance] model];

    NSDictionary *attributes = [NSDictionary dictionaryWithContentsOfFile:file];
    CLog(@"Got attributes: %@", attributes);

    NSMutableArray *stackIcons = [NSMutableArray arrayWithCapacity:(((NSArray *)attributes[STKStackManagerStackIconsKey]).count)];
    for (NSString *identifier in attributes[STKStackManagerStackIconsKey]) {
        // Get the SBIcon instances for the identifiers
        SBApplicationIcon *icon = [model applicationIconForDisplayIdentifier:identifier];
        if (!icon) {
            NSString *message = [NSString stringWithFormat:@"Couldn't get icon for identifier %@. Confirm that the ID is correct and the app is installed.", identifier];
            SHOW_USER_NOTIFICATION(kSTKTweakName, message, @"Dismiss");
            return nil;
        }
        [stackIcons addObject:[model applicationIconForDisplayIdentifier:identifier]];
    }

    SBApplicationIcon *centralIcon = [model applicationIconForDisplayIdentifier:attributes[STKStackManagerCentralIconKey]];
    if (!centralIcon) {
        SHOW_USER_NOTIFICATION(kSTKTweakName, @"Could not get the central icon for the stack", @"Dismiss");
        return nil;
    }

    return [self initWithCentralIcon:centralIcon stackIcons:stackIcons];
}

- (instancetype)initWithCentralIcon:(SBIcon *)centralIcon stackIcons:(NSArray *)icons
{
    if ((self = [super init])) {
        [icons retain]; // Make sure it's not released until we're done with it

        _centralIcon          = [centralIcon retain];

        _appearingIconsLayout = [[STKIconLayoutHandler layoutForIcons:icons aroundIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
        _displacedIconsLayout = [[STKIconLayoutHandler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconsLayout] retain];

        [icons release];

        [self _calculateDistanceRatio];
        [self _findIconsWithOffScreenTargets];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editingStateChanged:) name:STKEditingStateChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(__animateOpen) name:@"OpenSesame" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(__animateClosed) name:@"CloseSesame" object:nil];
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
    
    [_centralIcon release];
    [_interactionHandler release];
    [_appearingIconsLayout release];
    [_displacedIconsLayout release];
    [_iconViewsTable release];
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
    NSArray *stackIcons = [[_appearingIconsLayout allIcons] retain];

    [_appearingIconsLayout release];
    [_displacedIconsLayout release];

    _appearingIconsLayout = [[STKIconLayoutHandler layoutForIcons:stackIcons aroundIconAtPosition:[self _locationMaskForIcon:_centralIcon]] retain];
    [stackIcons release];

    _displacedIconsLayout = [[STKIconLayoutHandler layoutForIconsToDisplaceAroundIcon:_centralIcon usingLayout:_appearingIconsLayout] retain];

    [self _calculateDistanceRatio];
    [self _findIconsWithOffScreenTargets];
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
    _iconViewsTable = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory capacity:4];
    
    // SBIconListView *listView = STKListViewForIcon(_centralIcon);
    SBIconView *centralIconView = [[objc_getClass("SBIconViewMap") homescreenMap] iconViewForIcon:_centralIcon];


    [_appearingIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconView *iconView = [[[objc_getClass("SBIconView") alloc] initWithDefaultSize] autorelease];
        
        [iconView setIcon:icon];
        [iconView setDelegate:self];

        iconView.frame = centralIconView.bounds;
        iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);

        NSString *mapTableKey = [self _keyForPosition:position];

        NSMutableArray *iconViews = [_iconViewsTable objectForKey:mapTableKey];
        if (!iconViews) {
            iconViews = [NSMutableArray array];
        }
        [iconViews addObject:iconView];
        [_iconViewsTable setObject:iconViews forKey:mapTableKey];
        [iconView setIconLabelAlpha:0.f];
        [[iconView valueForKeyPath:@"_shadow"] setAlpha:0.f];

        // Insert subviews such that the appearing icons not in the first position slide out from under the previous icon
        if (index == 0) {
            [centralIconView insertSubview:iconView atIndex:0];
        }
        else {
            [centralIconView insertSubview:iconView belowSubview:iconViews[index - 1]];    
        }
        

        for (UIGestureRecognizer *recognizer in iconView.gestureRecognizers) {
            if ([recognizer isKindOfClass:[UISwipeGestureRecognizer class]]) {
                // Remove Velox BS.
                [iconView removeGestureRecognizer:recognizer];
            }
        }
    }];

    _hasSetup = YES;
}

- (void)cleanupView
{
    MAP([self _allAppearingIconViews], ^(SBIconView *iconView) {
        [iconView removeFromSuperview];
    });

    [_iconViewsTable release];
    _iconViewsTable = nil;

    _hasSetup = NO;
}

#pragma mark - Preview Handling
- (void)setupPreview
{
    [self setupViewIfNecessary];

    /*
    *   BULLSHIT CODE BEGINS
    */
    STKLayoutPosition positions[] = {STKLayoutPositionTop, STKLayoutPositionBottom, STKLayoutPositionLeft, STKLayoutPositionRight};
    for (NSInteger i = 0; i <= 3; i++) {
        NSArray *iconViews = [_iconViewsTable objectForKey:[self _keyForPosition:positions[i]]];
        STKLayoutPosition position = positions[i];

        [iconViews enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
            CGRect frame = [self _iconViewForIcon:_centralIcon].bounds;
            CGPoint newOrigin = frame.origin;

            // Check if it's the last object
            if (idx == iconViews.count - 1) {
                iconView.alpha = 1.f;

                // This is probably how the rest of the code should've been written
                CGFloat *memberToModify = ((position == STKLayoutPositionTop || position == STKLayoutPositionBottom) ? &newOrigin.y : &newOrigin.x);

                // the member to modify needs to be subtracted from in case of t/l.
                CGFloat negator = (position == STKLayoutPositionTop || position == STKLayoutPositionLeft ? -1 : 1);

                *memberToModify += 9 * negator;
            }
            else {
                // Only the last icon at a particular side needs to be shown
                iconView.alpha = 0.f;
            }

            frame.origin = newOrigin; 
            iconView.frame = frame;

            // Scale the icon back down to the smaller size.
            iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);
        }];
    }
    /*
    *   BULLSHIT CODE ENDS
    */
}

#pragma mark - Moving Icons
- (void)touchesDraggedForDistance:(CGFloat)distance
{
    if (_isExpanded && ![[[objc_getClass("SBIconController") sharedInstance] scrollView] isDragging]) {
        return;
    }
    
    if (!_hasPreparedGhostlyIcons) {
        [[objc_getClass("SBIconController") sharedInstance] prepareToGhostCurrentPageIconsForRequester:kGhostlyRequesterID skipIcon:_centralIcon];
        _hasPreparedGhostlyIcons = YES;
    }
    __stackInMotion = YES;

    [self _moveAllIconsInRespectiveDirectionsByDistance:distance];
    
    CGFloat alpha = STKAlphaFromDistance(_lastDistanceFromCenter);
    [self _setGhostlyAlphaForAllIcons:alpha excludingCentralIcon:YES];
    [self _setAlphaForAppearingLabelsAndShadows:(1 - alpha)];
    [self _setPageControlAlpha:alpha];

    
    CGFloat midWayDistance = STKGetCurrentTargetDistance() / 2.0;
    if (_lastDistanceFromCenter <= midWayDistance) {
        // If the icons are past the halfway mark, start increasing/decreasing their scale.
        // This looks beatuiful. Yay me.
        CGFloat stackIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kStackPreviewIconScale);
        MAP([self _allAppearingIconViews], ^(SBIconView *iconView) {
            iconView.iconImageView.transform = CGAffineTransformMakeScale(stackIconTransformScale, stackIconTransformScale);
        });

        CGFloat centralIconTransformScale = STKScaleNumber(_lastDistanceFromCenter, midWayDistance, 0, 1.0, kCentralIconPreviewScale);
        [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(centralIconTransformScale, centralIconTransformScale);
    }

    __stackInMotion = NO;
}

- (void)touchesEnded
{
    if (_lastDistanceFromCenter >= kEnablingThreshold && !_isExpanded) {
        [self openStack];
    }
    else {
        [self _animateToClosedPositionWithCompletionBlock:^{
            if (_interactionHandler) {
                _interactionHandler(nil);
            }
        } duration:kAnimationDuration animateCentralIcon:NO];
    }
}
 
- (void)closeStackWithCompletionHandler:(void(^)(void))completionHandler
{
    [self _animateToClosedPositionWithCompletionBlock:^{
        if (completionHandler) {
            completionHandler();
        }
    } duration:kAnimationDuration animateCentralIcon:YES];
}

- (void)closeStackSettingCentralIcon:(SBIcon *)icon completion:(void(^)(void))handler
{
    SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];

    [centralIconView setIcon:icon];
    
    [self closeStackWithCompletionHandler:^{
        if (handler) {
            handler();
        }
        EXECUTE_BLOCK_AFTER_DELAY(0.25, ^{
            // Okay, this is a hack, and not really OOP compliant. The 0.25 second delay is given so that when handler() launches an app, the central icon doesn't flash back quickly to the original
            [centralIconView setIcon:_centralIcon];
        });
    }];
}

- (void)openStack
{
    [self _animateToOpenPositionWithDuration:kAnimationDuration];
}

- (void)closeStack
{
    [self closeStackWithCompletionHandler:nil];
}

- (void)closeStackAfterDelay:(NSTimeInterval)delay completion:(void(^)(void))completionBlock
{
    EXECUTE_BLOCK_AFTER_DELAY(delay, ^{
        [self closeStackWithCompletionHandler:completionBlock];
    });
}

#pragma mark - Setter/Getter Overrides
- (void)setIsEditing:(BOOL)isEditing
{
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

#pragma mark - Open Animation
- (void)_animateToOpenPositionWithDuration:(NSTimeInterval)duration;
{
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self _iconViewForIcon:_centralIcon].iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);

        STKLayoutPosition positions[4] = {STKLayoutPositionTop, STKLayoutPositionBottom, STKLayoutPositionLeft, STKLayoutPositionRight};

        for (NSInteger i = 0; i <= 3; i++) {
            NSArray *iconViews = [_iconViewsTable objectForKey:[self _keyForPosition:positions[i]]];
            [iconViews enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
                CGRect newFrame = iconView.frame;
                
                newFrame.origin = [self _targetOriginForIconAtPosition:(STKLayoutPosition)[[STKIconLayout allPositions][i] integerValue] distanceFromCentre:idx + 1];
                iconView.frame = newFrame;
                iconView.iconImageView.transform = CGAffineTransformMakeScale(1.f, 1.f);
                
                iconView.delegate = self;
            }];
        }

        [_displacedIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition position) {
            SBIconView *iconView = [self _iconViewForIcon:icon];
            CGRect newFrame = iconView.frame;
            newFrame.origin = [self _displacedOriginForIcon:icon withPosition:position];
            iconView.frame = newFrame;
        }];

        [self _setPageControlAlpha:0];
        [self _setGhostlyAlphaForAllIcons:0.f excludingCentralIcon:YES];
        [self _setAlphaForAppearingLabelsAndShadows:1];

        [_offScreenIconsLayout enumerateThroughAllIconsUsingBlock:^(SBIcon *icon, STKLayoutPosition pos) {
            [self _iconViewForIcon:icon].alpha = 0.f;
        }];
        
    } completion:^(BOOL finished) {
        if (finished) {
            SBIconView *centralIconView = [self _iconViewForIcon:_centralIcon];
            _previousDelegate = centralIconView.delegate;
            centralIconView.delegate = self;

            [self _setupGestureRecognizers];
            [self _setGhostlyAlphaForAllIcons:0.f excludingCentralIcon:YES];

            _isExpanded = YES;
            __isStackOpen = YES;
        }
    }];
}


#pragma mark - Close Animation
- (void)_animateToClosedPositionWithCompletionBlock:(void(^)(void))completionBlock duration:(NSTimeInterval)duration animateCentralIcon:(BOOL)animateCentralIcon
{
    UIView *centralView = [[self _iconViewForIcon:_centralIcon] iconImageView];
    [UIView animateWithDuration:(duration / 2.0) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        // Animate central imageview shrink/grow
        if (animateCentralIcon) {
            centralView.transform = CGAffineTransformMakeScale(kCentralIconPreviewScale - 0.1f, kCentralIconPreviewScale - 0.1f);
        }
    } completion:^(BOOL finished) {
        if (finished) {
            // Animate it back to the preview icon scale
            [UIView animateWithDuration:(duration / 2.0) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                centralView.transform = CGAffineTransformMakeScale(kCentralIconPreviewScale, kCentralIconPreviewScale);
            } completion:nil];
        }
    }];
    
    // Make sure we're not in the editing state
    self.isEditing = NO;

    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        MAP([self _allAppearingIconViews], ^(SBIconView *iconView) {
            iconView.frame = [self _iconViewForIcon:_centralIcon].bounds;
            iconView.iconImageView.transform = CGAffineTransformMakeScale(kStackPreviewIconScale, kStackPreviewIconScale);
            ((UIImageView *)[iconView valueForKey:@"_shadow"]).alpha = 0.f;
            [iconView setIconLabelAlpha:0.f];
        });

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
            for (SBIconView *iconView in [self _allAppearingIconViews]) {
                iconView.delegate = nil;
            }

            [UIView animateWithDuration:kAnimationDuration animations:^{ [self setupPreview]; }];

            // XXX: BUGFIX for SBIconListView BS
            [self _setGhostlyAlphaForAllIcons:.9999999f excludingCentralIcon:NO]; // .999f is necessary, unfortunately. A weird 1.0->0.0->1.0 alpha flash happens otherwise
            [self _setGhostlyAlphaForAllIcons:1.f excludingCentralIcon:NO]; // Set it back to 1.f, fix a pain in the ass bug
            [[objc_getClass("SBIconController") sharedInstance] cleanUpGhostlyIconsForRequester:kGhostlyRequesterID];
            _hasPreparedGhostlyIcons = NO;
            
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
- (void)_moveAllIconsInRespectiveDirectionsByDistance:(CGFloat)distance
{
    /*
        MUST READ. 
        There is a lot of repetitive code down here, but it's there for a reason. I have outlined a few points below:
            • Having those checks keeps it easy to understanc
            • It is very easy to simply just do a little magic on the signs of the distance, etc. But that's what I want to avoid. I'd by far prefer code that still makes sense.
            • IMO, MAGIC IS ___NOT___ good when you're performing it.... LULZ.

        Comments are written everywhere to make sure that this code is understandable, even a few months down the line. For both appearing and disappearing icons, the first (top) set of icons have been commented, the l/r/d sets do the same thing, only in different directions, so it should be pretty simple to understand.
    */

    [_displacedIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        SBIconListView *listView = STKListViewForIcon(_centralIcon);
        SBIconView *iconView = [self _iconViewForIcon:icon];
        CGRect newFrame = iconView.frame;
        CGPoint originalOrigin = [listView originForIcon:icon];
        CGPoint targetOrigin = [self _displacedOriginForIcon:icon withPosition:position]; 

        NSUInteger appearingIconsCount = [self _appearingIconsForPosition:position].count;
        // Factor the distance up by the number of icons that are coming in at that position
        CGFloat factoredDistance = (distance * appearingIconsCount); 
        
        CGFloat horizontalFactoredDistance = factoredDistance * _distanceRatio; // The distance to be moved horizontally is slightly different than vertical, multiply it by the ratio to have them work perfectly. :)

        switch (position) {
            case STKLayoutPositionTop: {
                // If, after moving, the icon would pass its target, factor the distance back to it's original, for now it has to move as much as all the other icons only
                if ((newFrame.origin.y - (factoredDistance / appearingIconsCount)) < targetOrigin.y) {
                    factoredDistance /= appearingIconsCount;
                }

                targetOrigin.y -= kBandingAllowance; // Allow the icon to move for `kBandingAllowance` points beyond its target, simulating a 
                if ((newFrame.origin.y - factoredDistance) < targetOrigin.y) {
                    // If moving the icon by `factoredDistance` would cause it to move beyond its target, make it stick to the target location
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.y - factoredDistance) > originalOrigin.y) {
                    // If moving the icon by `factoredDistance` takes it beyond it's original location on the homescreen, make it stick again.
                    // This is necessary in cases when the swipe is coming back home.
                    newFrame.origin = originalOrigin;
                }
                else {
                    // If none of the above cases are true, move icon upwards (hence subtracted) by factored distance
                    newFrame.origin.y -= factoredDistance;
                }
                break;
            }
            case STKLayoutPositionBottom: {
                if ((newFrame.origin.y + (factoredDistance / appearingIconsCount)) > targetOrigin.y) {
                    factoredDistance /= appearingIconsCount;
                }

                targetOrigin.y += kBandingAllowance;
                if ((newFrame.origin.y + factoredDistance) > targetOrigin.y) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.y + factoredDistance) < originalOrigin.y) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.y += factoredDistance;
                }
                break;
            }
            case STKLayoutPositionLeft: {
                if ((newFrame.origin.x - (horizontalFactoredDistance / appearingIconsCount)) < targetOrigin.x) {
                    horizontalFactoredDistance /= appearingIconsCount;
                }

                targetOrigin.x -= kBandingAllowance * _distanceRatio;
                if ((newFrame.origin.x - horizontalFactoredDistance) < targetOrigin.x) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.x - horizontalFactoredDistance) > originalOrigin.x) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.x -= horizontalFactoredDistance;
                }
                break;
            }
            case STKLayoutPositionRight: {
                if ((newFrame.origin.x + (horizontalFactoredDistance / appearingIconsCount)) > targetOrigin.x) {
                    horizontalFactoredDistance /= appearingIconsCount;
                }

                targetOrigin.x += kBandingAllowance * _distanceRatio;
                if ((newFrame.origin.x + horizontalFactoredDistance) > targetOrigin.x) {
                    newFrame.origin = targetOrigin;
                }
                else if ((newFrame.origin.x + horizontalFactoredDistance) < originalOrigin.x) {
                    newFrame.origin = originalOrigin;
                }
                else {
                    newFrame.origin.x += horizontalFactoredDistance;
                }
                break;
            }

            default: {
                break;
            }
        }
        iconView.frame = newFrame;
    }];

    // Move stack icons
    CGRect centralFrame = [self _iconViewForIcon:_centralIcon].bounds;

    [(NSArray *)[_iconViewsTable objectForKey:STKStackTopIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        if (idx == 0) {
            _lastDistanceFromCenter = fabsf(iconView.frame.origin.y - centralFrame.origin.y);
        }    
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _targetOriginForIconAtPosition:STKLayoutPositionTop distanceFromCentre:idx + 1];

        // If there is more than one icon in a particular position, multiply them by their respective positions.
        // For example, the second icon in the top position needs to move a larger distance than the first, hence multiply the distance by 2, so it reaches its target the same time as the previous one.
        // Also, only multiply it if it isn't past the target point. At that point, it should move as much as everything else.
        CGFloat multiplicationFactor = (((newFrame.origin.y - distance) > targetOrigin.y) ? (idx + 1) : 1);
        CGFloat translatedDistance = distance * multiplicationFactor;

        targetOrigin.y -= kBandingAllowance;
        iconView.alpha = 1.f;
        
        if (((newFrame.origin.y - translatedDistance) > targetOrigin.y) && !((newFrame.origin.y - translatedDistance) > centralFrame.origin.y)) {
            newFrame.origin.y -= translatedDistance;
        }
        // If it's going beyond the acceptable limit, make it stick to the max position. The same thing is done in all the arrays below
        else if ((newFrame.origin.y - translatedDistance) < targetOrigin.y) {
            newFrame.origin = targetOrigin;
        }
        else if ((newFrame.origin.y - translatedDistance) > centralFrame.origin.y) {
            newFrame = [self _iconViewForIcon:_centralIcon].frame;
        }
        iconView.frame = newFrame;
    }];
    
    [(NSArray *)[_iconViewsTable objectForKey:STKStackBottomIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        if (idx == 0) {
            _lastDistanceFromCenter = fabsf(iconView.frame.origin.y - centralFrame.origin.y);
        }
        
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _targetOriginForIconAtPosition:STKLayoutPositionBottom distanceFromCentre:idx + 1];

        CGFloat multiplicationFactor = (((newFrame.origin.y + distance) < targetOrigin.y) ? (idx + 1) : 1);
        CGFloat translatedDistance = distance * multiplicationFactor;

        targetOrigin.y += kBandingAllowance;
        iconView.alpha = 1.f;

        if ((newFrame.origin.y + translatedDistance) < targetOrigin.y && !((newFrame.origin.y + translatedDistance) < centralFrame.origin.y)) {
            newFrame.origin.y += translatedDistance;
        }
        else if ((newFrame.origin.y + translatedDistance) > targetOrigin.y) {
            newFrame.origin = targetOrigin;
        }
        else if ((newFrame.origin.y + translatedDistance) < centralFrame.origin.y) {
            newFrame = centralFrame;
        }
        iconView.frame = newFrame;
    }];

    [(NSArray *)[_iconViewsTable objectForKey:STKStackLeftIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {        
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _targetOriginForIconAtPosition:STKLayoutPositionLeft distanceFromCentre:idx + 1];

        CGFloat multiplicationFactor = (((newFrame.origin.x - distance) > targetOrigin.x) ? (idx + 1) : 1);
        CGFloat translatedDistance = distance * multiplicationFactor * _distanceRatio;

        targetOrigin.x -= kBandingAllowance * _distanceRatio;
        iconView.alpha = 1.f;
        
        if (((newFrame.origin.x - translatedDistance) > targetOrigin.x) && !((newFrame.origin.x - translatedDistance) > centralFrame.origin.x)) {
            newFrame.origin.x -= translatedDistance;
        }
        else if ((newFrame.origin.x - translatedDistance) < targetOrigin.x) {
            newFrame.origin = targetOrigin;
        }
        else if ((newFrame.origin.x - translatedDistance) > centralFrame.origin.x) {
            newFrame = centralFrame;
        }
        iconView.frame = newFrame;
    }];

    [(NSArray *)[_iconViewsTable objectForKey:STKStackRightIconsKey] enumerateObjectsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        CGRect newFrame = iconView.frame;
        CGPoint targetOrigin = [self _targetOriginForIconAtPosition:STKLayoutPositionRight distanceFromCentre:idx + 1];
        
        CGFloat multiplicationFactor = (((newFrame.origin.x + distance) < targetOrigin.x) ? (idx + 1) : 1);
        CGFloat translatedDistance = distance * multiplicationFactor * _distanceRatio;

        targetOrigin.x += kBandingAllowance * _distanceRatio;
        iconView.alpha = 1.f;
        
        if (((newFrame.origin.x + translatedDistance) < targetOrigin.x) && !((newFrame.origin.x + translatedDistance) < centralFrame.origin.x)) {
            newFrame.origin.x += translatedDistance;
        }
        else if ((newFrame.origin.x + translatedDistance) > targetOrigin.x) {
            newFrame.origin = targetOrigin;
        }
        else if ((newFrame.origin.x + translatedDistance) < centralFrame.origin.x) {
            newFrame = centralFrame;
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

        for (SBIconView *iconView in [self _allAppearingIconViews]) {
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

        default: {
            break;
        }
    }
    
    return returnPoint;
}

- (CGPoint)_displacedOriginForIcon:(SBIcon *)icon withPosition:(STKLayoutPosition)position
{
    return [self _displacedOriginForIcon:icon withPosition:position usingLayout:_appearingIconsLayout];
}

- (CGFloat)_distanceFromCentre:(CGPoint)point
{
    SBIconView *iconView = [self _iconViewForIcon:_centralIcon];
    return sqrtf(((point.x - iconView.center.x) * (point.x - iconView.center.x)) + ((point.y - iconView.center.y)  * (point.y - iconView.center.y))); // distance formula
}

- (void)_makeAllIconsPerformBlock:(void(^)(SBIcon *))block
{
    SBIconListView *currentListView = STKListViewForIcon(_centralIcon);
    for (SBIcon *icon in currentListView.icons) {
        block(icon);
    }
    
    SBDockIconListView *dockView = [[objc_getClass("SBIconController") sharedInstance] dock];
    for (SBIcon *icon in dockView.icons) {    
        block(icon);
    }
}

- (id)_keyForPosition:(STKLayoutPosition)position
{
    return (position == STKLayoutPositionTop ? STKStackTopIconsKey : (position == STKLayoutPositionBottom ? STKStackBottomIconsKey : (position == STKLayoutPositionLeft ? STKStackLeftIconsKey : (position == STKLayoutPositionRight ? STKStackRightIconsKey : nil))));
}

- (NSArray *)_appearingIconsForPosition:(STKLayoutPosition)position
{
    return ((position == STKLayoutPositionTop) ? _appearingIconsLayout.topIcons : (position == STKLayoutPositionBottom) ? _appearingIconsLayout.bottomIcons : (position == STKLayoutPositionLeft) ? _appearingIconsLayout.leftIcons : _appearingIconsLayout.rightIcons);   
}

- (NSArray *)_appearingIconViewsForPosition:(STKLayoutPosition)position
{
    switch (position) {
        case STKLayoutPositionTop: {
            return [_iconViewsTable objectForKey:STKStackTopIconsKey];
        }
        case STKLayoutPositionBottom: {
            return [_iconViewsTable objectForKey:STKStackBottomIconsKey];
        }
        case STKLayoutPositionLeft: {
            return [_iconViewsTable objectForKey:STKStackLeftIconsKey];
        }
        case STKLayoutPositionRight: {
            return [_iconViewsTable objectForKey:STKStackRightIconsKey];
        }
        default: {
            return nil;
        }
    }
}

- (NSArray *)_allAppearingIconViews
{
    NSMutableArray *allTheThings = [NSMutableArray array];

    for (NSArray *iconViews in [[_iconViewsTable objectEnumerator] allObjects]) {
        [allTheThings addObjectsFromArray:iconViews];
    }

    return [[allTheThings copy] autorelease];
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

- (void)_findIconsWithOffScreenTargets
{
    [_offScreenIconsLayout release];
    _offScreenIconsLayout = [[STKIconLayout alloc] init]; 


    [_displacedIconsLayout enumerateIconsUsingBlockWithIndexes:^(SBIcon *icon, STKLayoutPosition position, NSArray *currentArray, NSUInteger index) {
        CGRect listViewBounds = STKListViewForIcon(_centralIcon).bounds;

        CGPoint target = [self _displacedOriginForIcon:icon withPosition:position];
        CGRect genericFrame = [self _iconViewForIcon:_centralIcon].frame;

        CGRect targetRect = (CGRect) {{target.x, target.y}, {genericFrame.size.width, genericFrame.size.height}}; // Create the icon's target rect using width and height from the central icon view.

        switch (position) {
            case STKLayoutPositionTop: {
                if (CGRectGetMaxY(targetRect) <= (listViewBounds.origin.y + 20)) {
                    // Add 20 to account for status bar frame
                    [_offScreenIconsLayout addIcon:icon toIconsAtPosition:position];
                }
                break;
            }

            case STKLayoutPositionBottom: {
                if (CGRectGetMidY(targetRect) >= CGRectGetHeight(listViewBounds)) {
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
- (void)_setAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)shouldExcludeCentral disableInteraction:(BOOL)disableInteraction
{
    [self _makeAllIconsPerformBlock:^(SBIcon *icon) {
        if (shouldExcludeCentral && ([icon.leafIdentifier isEqualToString:_centralIcon.leafIdentifier])) {
            return;
        }
        SBIconView *iconView = [self _iconViewForIcon:icon];
        iconView.alpha = alpha;
        iconView.userInteractionEnabled = !disableInteraction;
    }];
}

- (void)_setGhostlyAlphaForAllIcons:(CGFloat)alpha excludingCentralIcon:(BOOL)excludeCentral
{
    if (alpha >= 1.f) {
        [[objc_getClass("SBIconController") sharedInstance] setCurrentPageIconsGhostly:NO forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];
    }
    else if (alpha <= 0.f) {
        [[objc_getClass("SBIconController") sharedInstance] setCurrentPageIconsGhostly:YES forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];   
    }
    else {
        [[objc_getClass("SBIconController") sharedInstance] setCurrentPageIconsPartialGhostly:alpha forRequester:kGhostlyRequesterID skipIcon:(excludeCentral ? _centralIcon : nil)];
    }

    for (SBIcon *icon in _offScreenIconsLayout.bottomIcons) {
        // Set the bottom offscreen icons' alpha now, because they look like shit overlapping the dock.
        [self _iconViewForIcon:icon].alpha = alpha;
    }
}

- (void)_setAlphaForAppearingLabelsAndShadows:(CGFloat)alpha
{
    for (SBIconView *iconView in [self _allAppearingIconViews]) {
        ((UIImageView *)[iconView valueForKey:@"_shadow"]).alpha = alpha;
        [iconView setIconLabelAlpha:alpha];
    }
}

- (void)_setInteractionEnabled:(BOOL)enabled forAllIconsExcludingCentral:(BOOL)shouldExcludeCentral
{
    [self _makeAllIconsPerformBlock:^(SBIcon *icon) {
        if (shouldExcludeCentral && ([icon.leafIdentifier isEqualToString:_centralIcon.leafIdentifier])) {
            return;
        }
        SBIconView *iconView = [self _iconViewForIcon:icon];
        iconView.userInteractionEnabled = enabled;
    }];
}

- (void)_setPageControlAlpha:(CGFloat)alpha
{
    [[objc_getClass("SBIconController") sharedInstance] setPageControlAlpha:alpha];
}


#pragma mark - Notification Handling
- (void)_editingStateChanged:(NSNotification *)notification
{
    if (_isExpanded) {
        self.isEditing = [[objc_getClass("SBIconController") sharedInstance] isEditing];
    }

    else if (![[objc_getClass("SBIconController") sharedInstance] isEditing] && self.closesOnHomescreenEdit) {
        [self closeStackWithCompletionHandler:^{
            if (_interactionHandler) {
                _interactionHandler(nil);
            }
        }];
    }
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

    MAP([self _allAppearingIconViews], addOverlayToView);
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

    MAP([self _allAppearingIconViews], removeOverlayFromView);
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
    [self _animateToClosedPositionWithCompletionBlock:nil duration:0.5 animateCentralIcon:YES];
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

    [iconView setHighlighted:YES delayUnhighlight:YES];
    if (_interactionHandler) {
        _interactionHandler(iconView);
    }
}

- (void)iconHandleLongPress:(SBIconView *)iconView
{
    [iconView setHighlighted:NO];
    self.isEditing = !(self.isEditing);
}

- (BOOL)iconShouldAllowTap:(SBIconView *)iconView
{
    return YES;
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
