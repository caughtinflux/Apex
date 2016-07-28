#import "STKGroupSelectionAnimator.h"
#import "STKConstants.h"
#import <SpringBoard/SpringBoard.h>
#import <SpringBoardFoundation/SBFAnimationSettings.h>
#import <SpringBoardFoundation/SBFWallpaperView.h>
#import <7_0_SpringBoard/SBRootZoomSettings.h>

@implementation STKGroupSelectionAnimator
{
    STKSelectionView *_selectionView;
    SBIconView *_iconView;
    SBScaleIconZoomAnimator *_zoomAnimator;
    CGFloat _startScale;
    CGPoint _startCenter;
}

- (instancetype)initWithSelectionView:(STKSelectionView *)selectionView iconView:(SBIconView *)iconView
{
    if ((self = [super init])) {
        _selectionView = [selectionView retain];
        _iconView = [iconView retain];
    }
    return self;
}

- (void)dealloc
{
    [_selectionView release];
    [_zoomAnimator release];
    [_iconView release];
    [super dealloc];
}

- (void)openSelectionViewAnimatedWithCompletion:(STKAnimatorCompletion)completion
{
    SBIconContentView *iconContentView = [(SBIconController *)[CLASS(SBIconController) sharedInstance] contentView];
    _selectionView.contentView.alpha = 0.0;
    _selectionView.searchTextField.alpha = 0.0;
    _selectionView.frame = iconContentView.bounds;
    [iconContentView addSubview:_selectionView];

    SBFolderController *currentFolderController = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _currentFolderController];
    SBPrototypeController *protoController = [CLASS(SBPrototypeController) sharedInstance];
    _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:currentFolderController targetIcon:_iconView.icon];

    SBRootSettings *rootSettings = [protoController rootSettings];
    id settings = nil;
    if ([rootSettings respondsToSelector:@selector(rootAnimationSettings)]) {
        settings = rootSettings.rootAnimationSettings.folderOpenSettings;
    }
    else if ([rootSettings respondsToSelector:@selector(rootZoomSettings)]) {
        settings = rootSettings.rootZoomSettings.folderOpenSettings;
    }
    else {
        settings = [[[CLASS(SBScaleZoomSettings) alloc] init] autorelease];
        [settings setDefaultValues];
    }
    if ([_zoomAnimator respondsToSelector:@selector(setSettings:)]) {
        _zoomAnimator.settings = settings;
    }
    else if ([_zoomAnimator respondsToSelector:@selector(setZoomSettings:)]) {
        _zoomAnimator.zoomSettings = settings;
    }
    [_zoomAnimator prepare];

    CGSize endSize = [CLASS(SBFolderBackgroundView) folderBackgroundSize];
    _startScale = ([_iconView _iconImageView].frame.size.width / endSize.width);
    _selectionView.contentView.bounds = (CGRect){CGPointZero, endSize};
    _selectionView.contentView.transform = CGAffineTransformMakeScale(_startScale, _startScale);
    _selectionView.iconCollectionView.frame = _selectionView.contentView.bounds;
    [_selectionView scrollToSelectedIconAnimated:NO];

    _startCenter = [_selectionView convertPoint:[_iconView iconImageCenter] fromView:_iconView];
    _selectionView.contentView.center = _startCenter;

    NSTimeInterval duration;
    if ([_zoomAnimator respondsToSelector:@selector(settings)]) {
        duration = _zoomAnimator.settings.crossfadeSettings.duration;
    }
    else {
        duration = _zoomAnimator.zoomSettings.crossfadeSettings.duration;
    }
    if ([protoController.rootSettings respondsToSelector:@selector(animationSettings)] && protoController.rootSettings.animationSettings.slowAnimations) {
        duration *= [protoController rootSettings].animationSettings.slowDownFactor;
    }
    CGFloat timeToAdd  = IS_7_1() ? 0.0 : 0.1;
    [UIView animateWithDuration:(duration + timeToAdd) delay:(duration * 0.1) options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        _selectionView.contentView.transform = CGAffineTransformIdentity;
        _selectionView.contentView.center = (CGPoint){CGRectGetMidX(_selectionView.bounds), CGRectGetMidY(_selectionView.bounds)};

        STKCurrentListView().alpha = 0.0;
        ((SBDockIconListView *)[[CLASS(SBIconController) sharedInstance] dockListView]).alpha = 0.0;
        _selectionView.contentView.alpha = 1.0;
        _selectionView.searchTextField.alpha = 1.0;

        SBWallpaperController *wallpaperController = [CLASS(SBWallpaperController) sharedInstance];
        CGFloat scale = [CLASS(SBFolderController) wallpaperScaleForDepth:1];
        [wallpaperController setHomescreenWallpaperScale:scale];
    } completion:nil];

    void (^zoomCompletion)(void) = ^{
        [_selectionView flashScrollIndicators];
        if (completion) {
            completion();
        }
    };
    if ([_zoomAnimator respondsToSelector:@selector(animateToFraction:afterDelay:withCompletion:)]) {
        [_zoomAnimator animateToFraction:1.0 afterDelay:0.0 withCompletion:zoomCompletion];
    }
    else if ([_zoomAnimator respondsToSelector:@selector(animateToZoomFraction:afterDelay:withCompletion:)]) {
        [_zoomAnimator animateToZoomFraction:1.0 afterDelay:0.0 withCompletion:zoomCompletion];
    }
}

- (void)closeSelectionViewAnimatedWithCompletion:(STKAnimatorCompletion)completion
{
    SBPrototypeController *protoController = [CLASS(SBPrototypeController) sharedInstance];
    SBRootSettings *rootSettings = [protoController rootSettings];
    id settings = nil;
    if ([rootSettings respondsToSelector:@selector(rootAnimationSettings)]) {
        settings = rootSettings.rootAnimationSettings.folderCloseSettings;
    }
    else if ([rootSettings respondsToSelector:@selector(rootZoomSettings)]) {
        settings = rootSettings.rootZoomSettings.folderCloseSettings;
    }
    else {
        settings = [[[CLASS(SBScaleZoomSettings) alloc] init] autorelease];
        [settings setDefaultValues];
    }
    if ([_zoomAnimator respondsToSelector:@selector(setSettings:)]) {
        _zoomAnimator.settings = settings;
    }
    else if ([_zoomAnimator respondsToSelector:@selector(setZoomSettings:)]) {
        _zoomAnimator.zoomSettings = settings;
    }

    NSTimeInterval duration;
    if ([_zoomAnimator respondsToSelector:@selector(settings)]) {
        duration = _zoomAnimator.settings.crossfadeSettings.duration;
    }
    else {
        duration = _zoomAnimator.zoomSettings.crossfadeSettings.duration;
    }
    if ([protoController.rootSettings respondsToSelector:@selector(animationSettings)] &&
         protoController.rootSettings.animationSettings.slowAnimations) {
        duration *= [protoController rootSettings].animationSettings.slowDownFactor;
    }
    [UIView animateWithDuration:duration delay:0.0 options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        _selectionView.searchTextField.alpha = 0.0;
        _selectionView.iconCollectionView.alpha = 0.0;
    } completion:nil];
    CGFloat timeToAdd  = IS_7_1() ? 0.0 : 0.1;
    [UIView animateWithDuration:(duration + timeToAdd) delay:(duration * 0.1) options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        CGAffineTransform scalingTransform = CGAffineTransformMakeScale(_startScale, _startScale);
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation((_startCenter.x - _selectionView.contentView.center.x),
                                                                                  (_startCenter.y - _selectionView.contentView.center.y));
        CGAffineTransform finalTransform = CGAffineTransformConcat(scalingTransform, translationTransform);
        _selectionView.contentView.transform = finalTransform;

        _selectionView.backgroundView.alpha = 0.0;
        STKCurrentListView().alpha = 1.0;
        ((SBDockIconListView *)[[CLASS(SBIconController) sharedInstance] dockListView]).alpha = 1.0;

        SBWallpaperController *wallpaperController = [CLASS(SBWallpaperController) sharedInstance];
        CGFloat scale = [CLASS(SBFolderController) wallpaperScaleForDepth:0];
        [wallpaperController setHomescreenWallpaperScale:scale];
    } completion:nil];

    void (^zoomCompletion)(void) = ^{
        SBIconView *centralIconView = [_zoomAnimator iconViewForIcon:[_iconView containerGroupView].group.centralIcon];
        if ((centralIconView.location == SBIconLocationFolder) || (centralIconView.location == SBIconLocationFolder_7_1) || IS_8_1()) {
            VLog(@"%@", _iconView);
            [_zoomAnimator cleanup];
            VLog(@"%@", @(_iconView.hidden));
            VLog(@"%@", _iconView.icon);
        }
        [_zoomAnimator release];
        _zoomAnimator = nil;
        if (completion) {
            completion();
        }
    };
    if ([_zoomAnimator respondsToSelector:@selector(animateToFraction:afterDelay:withCompletion:)]) {
        [_zoomAnimator animateToFraction:0.0 afterDelay:0.0 withCompletion:zoomCompletion];
    }
    else if ([_zoomAnimator respondsToSelector:@selector(animateToZoomFraction:afterDelay:withCompletion:)]) {
        [_zoomAnimator animateToZoomFraction:0.0 afterDelay:0.0 withCompletion:zoomCompletion];
    }
}

@end
