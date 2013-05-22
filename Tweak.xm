#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "STKConstants.h"
#import "STKStackManager.h"
#import "STKRecognizerDelegate.h"
#import "STKPreferences.h"

#import <SpringBoard/SpringBoard.h>

#pragma mark - Function Declarations
// Creates an STKStackManager object, sets it as an associated object on `iconView`, and returns it.
static STKStackManager * STKSetupManagerForView(SBIconView *iconView);

// Removes the manager from view, closing the stack if it was open
static void STKRemoveManagerFromView(SBIconView *iconView);

static void STKAddPanRecognizerToIconView(SBIconView *iconView);
static void STKRemovePanRecognizerFromIconView(SBIconView *iconView);

static void STKAddGrabberImagesToIconView(SBIconView *iconView);
static void STKRemoveGrabberImagesFromIconView(SBIconView *iconView);

// Adds recogniser and grabber images
static void STKSetupIconView(SBIconView *iconView);
// Removes recogniser and grabber images
static void STKCleanupIconView(SBIconView *iconView);
// Refreshes everything
static inline void STKRefreshIconViews(void);

// Inline Functions, prevent overhead if called too much.
static inline UIPanGestureRecognizer * STKPanRecognizerForView(SBIconView *iconView);
static inline STKStackManager        * STKManagerForView(SBIconView *iconView);
static inline NSString               * STKGetLayoutPathForIcon(SBIcon *icon);

#pragma mark - Direction !
typedef enum {
    STKRecognizerDirectionUp   = 0xf007ba11,
    STKRecognizerDirectionDown = 0x50f7ba11,
    STKRecognizerDirectionNone = 0x0ddba11
} STKRecognizerDirection;

// Returns the direction - top or bottom - for a given velocity
static inline STKRecognizerDirection STKDirectionFromVelocity(CGPoint point);


#pragma mark - SBIconView Hook
%hook SBIconView
- (void)setIcon:(SBIcon *)icon
{
    %orig();
    if (!icon ||
        self.location == SBIconViewLocationSwitcher ||
        [[%c(SBIconController) sharedInstance] isEditing] ||
        !([[[STKPreferences sharedPreferences] identifiersForIconsWithStack] containsObject:icon.leafIdentifier]))
    {
        // Make sure the recognizer is not added to icons in the stack
        // In the switcher, -setIcon: is called to change the icon, but doesn't change the icon view, make sure the recognizer is removed
        STKCleanupIconView(self);
        return;
    }
    STKSetupIconView(self);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stk_closeStack:) name:STKStackClosingEventNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stk_editingStateChanged:) name:STKEditingStateChangedNotification object:nil];
}

- (BOOL)canReceiveGrabbedIcon:(SBIconView *)iconView
{
    NSArray *iconsWithStack = [[STKPreferences sharedPreferences] identifiersForIconsWithStack];
    return ((([iconsWithStack containsObject:self.icon.leafIdentifier]) || ([iconsWithStack containsObject:iconView.icon.leafIdentifier])) ? NO : %orig());
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:STKStackClosingEventNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:STKEditingStateChangedNotification object:nil];

    %orig();
}

#define kBandingFactor  0.1 // The factor by which the distance should be multiplied when the icons have crossed kTargetDistance

static CGPoint                _previousPoint    = CGPointZero;
static CGPoint                _initialPoint     = CGPointZero;
static CGFloat                _previousDistance = 0.0f; // Contains the distance from the initial point.
static STKRecognizerDirection _currentDirection = STKRecognizerDirectionNone; // Stores the direction of the current pan.

%new
- (void)stk_panned:(UIPanGestureRecognizer *)sender
{
    SBIconListView *view = STKListViewForIcon(self.icon);
    STKStackManager *stackManager = STKManagerForView(self);
    if (stackManager.isExpanded) {
        return;
    }

    if (sender.state == UIGestureRecognizerStateBegan) {
        if (self.location == SBIconViewLocationSwitcher ||
            [[%c(SBIconController) sharedInstance] isEditing] || 
            !([[[STKPreferences sharedPreferences] identifiersForIconsWithStack] containsObject:self.icon.leafIdentifier]))
        {
            // Preliminary check
            STKCleanupIconView(self);
            return;
        }

        // Update the target distance based on icons positions when the pan begins
        // This way, we can be sure that the icons are indeed in the required location 
        STKUpdateTargetDistanceInListView(STKListViewForIcon(self.icon));

        if (stackManager && !stackManager.isExpanded) {
            // Create a new manager, I don't want the same one to be resused.
           //  Similar to folders.
            STKRemoveManagerFromView(self);
        }

        stackManager = STKSetupManagerForView(self);
        [stackManager setupViewIfNecessary];

        _initialPoint = [sender locationInView:view];
        _currentDirection = STKDirectionFromVelocity([sender velocityInView:view]);
        _previousPoint = _initialPoint; // Previous point is also initial at the start :P

        CGPoint translation = [sender translationInView:view];
        if ((fabsf(translation.x / translation.y) < 5.0) || translation.x == 0) {
            // Turn off scrolling if it's s vertical swipe
            [[%c(SBIconController) sharedInstance] scrollView].scrollEnabled = NO;
        }
    }

    else if (sender.state == UIGestureRecognizerStateChanged) {
        if ([[%c(SBIconController) sharedInstance] scrollView].isDragging) {
            return;
        }

        CGPoint point = [sender locationInView:view];

        BOOL hasCrossedInitial = NO;
        // If the swipe is going beyond the point where it started from, stop the swipe.
        if (_currentDirection == STKRecognizerDirectionUp) {
            hasCrossedInitial = (point.y > _initialPoint.y);
        }
        else if (_currentDirection == STKRecognizerDirectionDown) {
            hasCrossedInitial = (point.y < _initialPoint.y);
        }

        if (hasCrossedInitial) {
            return;
        }

        CGFloat change = fabsf(_previousPoint.y - point.y); // Vertical distances
        CGFloat distance = fabsf(_initialPoint.y - point.y);
        
        if (distance < _previousDistance || stackManager.isExpanded) {
            // The swipe is going to the opposite direction, so make sure the manager moves its views in the corresponding direction too
            change = -change;
        }


        if ((change > 0) && ((stackManager.currentIconDistance) >= STKGetCurrentTargetDistance())) {
            // Factor this down to simulate elasticity when the icons have reached their target locations
            // Stack manager allows the icons to go beyond their targets for a little distance
            change *= kBandingFactor;
        }

        [stackManager touchesDraggedForDistance:change];

        _previousPoint = point;
        _previousDistance = fabsf(distance);
    }

    else {
        [stackManager touchesEnded];

        // Reset the static vars
        _previousPoint = CGPointZero;
        _initialPoint = CGPointZero;
        _previousDistance = 0.f;
        _currentDirection = STKRecognizerDirectionNone;

        [[%c(SBIconController) sharedInstance] scrollView].scrollEnabled = YES;
    }
}

%new 
- (void)stk_editingStateChanged:(NSNotification *)notification
{
    BOOL isEditing = [[%c(SBIconController) sharedInstance] isEditing];
    
    if (isEditing) {
        STKCleanupIconView(self);
    }
    else {
        if ([[[STKPreferences sharedPreferences] identifiersForIconsWithStack] containsObject:self.icon.leafIdentifier] && (isEditing == NO)) {
            STKSetupIconView(self);
        }
    }
}

%new 
- (void)stk_closeStack:(NSNotification *)notification
{
    STKStackManager *manager = STKManagerForView(self);
    [manager closeStackWithCompletionHandler:^{
        STKRemoveManagerFromView(self);
    }];
}

%end

%hook SBIconController
- (void)setIsEditing:(BOOL)isEditing
{
    %orig(isEditing);
    [[NSNotificationCenter defaultCenter] postNotificationName:STKEditingStateChangedNotification object:nil];
}

/*  
    Various hooks to intercept events that should make the stack close
*/
- (void)iconWasTapped:(SBIcon *)icon
{
    if ([[[STKPreferences sharedPreferences] identifiersForIconsWithStack] containsObject:icon.leafIdentifier]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:STKStackClosingEventNotification object:nil];
    }
    
    %orig(icon);
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    %orig(scrollView);
    [[NSNotificationCenter defaultCenter] postNotificationName:STKStackClosingEventNotification object:nil];
}
%end

%hook SBUIController
- (BOOL)clickedMenuButton
{
    if ([STKStackManager anyStackOpen] || [STKStackManager anyStackInMotion]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:STKStackClosingEventNotification object:nil];
        return NO;// OOoooooooooooo
    }
    else {
        return %orig();
    }
}

- (BOOL)_activateSwitcher:(NSTimeInterval)animationDuration
{
    [[NSNotificationCenter defaultCenter] postNotificationName:STKStackClosingEventNotification object:nil];
    return %orig(animationDuration);
}

%end

#pragma mark - Associated Object Keys
static const char *panGRKey;
static const char *stackManagerKey;
static const char *topGrabberViewKey;
static const char *bottomGrabberViewKey;
static const char *recognizerDelegateKey;

#pragma mark - Static Function Definitions
static void STKAddPanRecognizerToIconView(SBIconView *iconView)
{
    UIPanGestureRecognizer *panRecognizer = objc_getAssociatedObject(iconView, &panGRKey);
    // Don't add a recognizer if it already exists
    if (!panRecognizer) {
        panRecognizer = [[[UIPanGestureRecognizer alloc] initWithTarget:iconView action:@selector(stk_panned:)] autorelease];
        [iconView addGestureRecognizer:panRecognizer];
        objc_setAssociatedObject(iconView, &panGRKey, panRecognizer, OBJC_ASSOCIATION_ASSIGN);

        // Setup a delegate, and have the recognizer retain it using associative refs, so that when the recognizer is destroyed, so is the delegate object
        STKRecognizerDelegate *delegate = [[STKRecognizerDelegate alloc] init];
        panRecognizer.delegate = delegate;
        objc_setAssociatedObject(panRecognizer, &recognizerDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN);
        [delegate release];
    }
}

static void STKRemovePanRecognizerFromIconView(SBIconView *iconView)
{
    UIPanGestureRecognizer *recognizer = STKPanRecognizerForView(iconView);
    [iconView removeGestureRecognizer:recognizer];

    // Clear out the associative references. 
    objc_setAssociatedObject(recognizer, &recognizerDelegateKey, nil, OBJC_ASSOCIATION_RETAIN); // Especially this one. The pan recogniser getting wiped out should remove this already. But still, better to be sure.
    objc_setAssociatedObject(iconView, &panGRKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void STKAddGrabberImagesToIconView(SBIconView *iconView)
{
    NSBundle *tweakBundle = [NSBundle bundleWithPath:@"/Library/Application Support/Acervos.bundle"];

    UIImageView *topView = objc_getAssociatedObject(iconView, &topGrabberViewKey);
    if (!topView) {
        UIImage *topImage = [[[UIImage alloc] initWithContentsOfFile:[tweakBundle pathForResource:@"TopGrabber" ofType:@"png"]] autorelease];
        topView = [[[UIImageView alloc] initWithImage:topImage] autorelease];
        topView.center = (CGPoint){iconView.iconImageView.center.x, (iconView.iconImageView.frame.origin.y)};
        [iconView addSubview:topView];

        objc_setAssociatedObject(iconView, &topGrabberViewKey, topView, OBJC_ASSOCIATION_ASSIGN);
    }

    UIImageView *bottomView = objc_getAssociatedObject(iconView, &bottomGrabberViewKey);
    if (!bottomView) {
        UIImage *bottomImage = [[[UIImage alloc] initWithContentsOfFile:[tweakBundle pathForResource:@"BottomGrabber" ofType:@"png"]] autorelease];
        bottomView = [[[UIImageView alloc] initWithImage:bottomImage] autorelease];
        bottomView.center = (CGPoint){iconView.iconImageView.center.x, (CGRectGetMaxY(iconView.iconImageView.frame) - 1)};
        [iconView addSubview:bottomView];

        objc_setAssociatedObject(iconView, &bottomGrabberViewKey, bottomView, OBJC_ASSOCIATION_ASSIGN);
    }
}

static void STKRemoveGrabberImagesFromIconView(SBIconView *iconView)
{
    [(UIView *)objc_getAssociatedObject(iconView, &topGrabberViewKey) removeFromSuperview];
    [(UIView *)objc_getAssociatedObject(iconView, &bottomGrabberViewKey) removeFromSuperview];  

    objc_setAssociatedObject(iconView, &topGrabberViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(iconView, &bottomGrabberViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static STKStackManager * STKSetupManagerForView(SBIconView *iconView)
{
    @autoreleasepool {

        STKStackManager * __block stackManager = STKManagerForView(iconView);
        if (stackManager) {
            // Make sure the current manager is removed, if it exists
            objc_setAssociatedObject(iconView, &stackManagerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            stackManager = nil;
        }

        NSString *layoutPath = [[STKPreferences sharedPreferences] layoutPathForIcon:iconView.icon];
        
        // Check if the manager can be created from file
        if ([[NSFileManager defaultManager] fileExistsAtPath:layoutPath]) { 
            stackManager = [[STKStackManager alloc] initWithContentsOfFile:layoutPath];
        }
        else {
            stackManager = [[STKStackManager alloc] initWithCentralIcon:iconView.icon stackIcons:[[STKPreferences sharedPreferences] stackIconsForIcon:iconView.icon]];
            [stackManager saveLayoutToFile:layoutPath];
        }

        STKStackManager * __block weakShit = stackManager;
        weakShit.interactionHandler = \
            ^(SBIconView *tappedIconView) {
                if (tappedIconView) {
                    [(SBUIController *)[%c(SBUIController) sharedInstance] launchIcon:tappedIconView.icon];
                    [stackManager closeStackSettingCentralIcon:tappedIconView.icon completion:^{
                        STKRemoveManagerFromView(iconView);
                    }];
                }
                else {
                    STKRemoveManagerFromView(iconView);
                }
            };


        objc_setAssociatedObject(iconView, &stackManagerKey, stackManager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stackManager release];
        
        return stackManager;
    }
}

static void STKRemoveManagerFromView(SBIconView *iconView)
{
    objc_setAssociatedObject(iconView, &stackManagerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void STKSetupIconView(SBIconView *iconView)
{
    STKAddPanRecognizerToIconView(iconView);
    STKAddGrabberImagesToIconView(iconView);
}

static void STKCleanupIconView(SBIconView *iconView)
{
    STKRemovePanRecognizerFromIconView(iconView);
    STKRemoveGrabberImagesFromIconView(iconView);
    STKRemoveManagerFromView(iconView);
}

static inline void STKRefreshIconViews(void)
{
}

#pragma mark - Inliner Definitions
static inline STKRecognizerDirection STKDirectionFromVelocity(CGPoint point)
{
    if (point.y == 0) {
        return STKRecognizerDirectionNone;
    }

    return ((point.y < 0) ? STKRecognizerDirectionUp : STKRecognizerDirectionDown);
}

static inline UIPanGestureRecognizer * STKPanRecognizerForView(SBIconView *iconView)
{
    return objc_getAssociatedObject(iconView, &panGRKey);
}

static inline STKStackManager * STKManagerForView(SBIconView *iconView)
{
    @autoreleasepool {
        return objc_getAssociatedObject(iconView, &stackManagerKey);
    }
}

#pragma mark - Constructor
%ctor
{
    @autoreleasepool {
        CLog(@"Acervos version %s", kPackageVersion);
        %init();
#ifdef DEBUG
        [STKPreferences sharedPreferences];
        NSDictionary *layout = @{STKStackManagerCentralIconKey : @"com.saurik.Cydia",
                                 STKStackManagerStackIconsKey  : @[@"com.apple.Preferences", @"eu.heinelt.ifile", @"com.apple.AppStore", @"com.apple.MobileStore"]};

        NSString *path = [[STKStackManager layoutsPath] stringByAppendingString:@"/com.saurik.Cydia.layout"];
        BOOL didWrite = [layout writeToFile:path atomically:YES];
        if (!didWrite) {
            CLog(@"Couldn't save default layout to %@", path);
        }
#endif
    }
}
