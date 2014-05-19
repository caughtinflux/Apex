#import "STKGroupSelectionAnimator.h"
#import "STKConstants.h"
#import <SpringBoard/SpringBoard.h>
#import <SpringBoardFoundation/SBFAnimationSettings.h>
#import <SpringBoardFoundation/SBFWallpaperView.h>

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
    _selectionView.contentView.alpha = 0.0f;
    _selectionView.searchTextField.alpha = 0.f;
    _selectionView.frame = iconContentView.bounds;
    [iconContentView addSubview:_selectionView];

    SBFolderController *currentFolderController = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _currentFolderController];
    _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:currentFolderController targetIcon:_iconView.icon];    
    _zoomAnimator.settings = [[CLASS(SBPrototypeController) sharedInstance] rootSettings].rootAnimationSettings.folderOpenSettings;
    [_zoomAnimator prepare];
    
    CGSize endSize = [CLASS(SBFolderBackgroundView) folderBackgroundSize];
    _startScale = ([_iconView _iconImageView].frame.size.width / endSize.width);
    _selectionView.contentView.bounds = (CGRect){CGPointZero, endSize};
    _selectionView.contentView.transform = CGAffineTransformMakeScale(_startScale, _startScale);
    _selectionView.iconCollectionView.frame = _selectionView.contentView.bounds;
    [_selectionView scrollToSelectedIconAnimated:NO];

    _startCenter = [_selectionView convertPoint:[_iconView iconImageCenter] fromView:_iconView];
    _selectionView.contentView.center = _startCenter;

    NSTimeInterval duration = _zoomAnimator.settings.outerFolderFadeSettings.duration;
    [_selectionView.backgroundView willAnimate];
    [UIView animateWithDuration:duration delay:0.05 options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        SBWallpaperController *wallpaperController = [CLASS(SBWallpaperController) sharedInstance];
        CGFloat scale = [CLASS(SBFolderController) wallpaperScaleForDepth:1];
        [wallpaperController setHomescreenWallpaperScale:scale];
        [_selectionView.backgroundView didAnimate];
        _selectionView.contentView.transform = CGAffineTransformIdentity;
        _selectionView.contentView.center = (CGPoint){CGRectGetMidX(_selectionView.bounds), CGRectGetMidY(_selectionView.bounds)};
        STKCurrentListView().alpha = 0.f;
        [[CLASS(SBIconController) sharedInstance] dockListView].alpha = 0.f;
        _selectionView.contentView.alpha = 1.0f;
        _iconView.alpha = 0.f;
        _selectionView.searchTextField.alpha = 1.f;
    } completion:nil];
    [_zoomAnimator animateToFraction:1.0 afterDelay:0.05 withCompletion:^{
        [_selectionView flashScrollIndicators];
        if (completion) {
            completion();
        }
    }];
}

- (void)closeSelectionViewAnimatedWithCompletion:(STKAnimatorCompletion)completion
{
    _zoomAnimator.settings = [[CLASS(SBPrototypeController) sharedInstance] rootSettings].rootAnimationSettings.folderCloseSettings;
    NSTimeInterval duration = [(SBFolderZoomSettings *)_zoomAnimator.settings innerFolderFadeSettings].duration;

    [UIView animateWithDuration:duration delay:0.0 options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        _selectionView.searchTextField.alpha = 0.f;
        _selectionView.iconCollectionView.alpha = 0.f;
    } completion:nil];
    [_selectionView.backgroundView willAnimate];
    [UIView animateWithDuration:(duration + 0.1) delay:(duration * 0.1) options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        _iconView.alpha = 1.f;
        CGAffineTransform scalingTransform = CGAffineTransformMakeScale(_startScale, _startScale);
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation((_startCenter.x - _selectionView.contentView.center.x),
                                                                                  (_startCenter.y - _selectionView.contentView.center.y + 10.0));
        CGAffineTransform finalTransform = CGAffineTransformConcat(scalingTransform, translationTransform);
        _selectionView.contentView.transform = finalTransform;
        _selectionView.backgroundView.alpha = 0.0f;
        STKCurrentListView().alpha = 1.f;
        [[CLASS(SBIconController) sharedInstance] dockListView].alpha = 1.f;

        SBWallpaperController *wallpaperController = [CLASS(SBWallpaperController) sharedInstance];
        CGFloat scale = [CLASS(SBFolderController) wallpaperScaleForDepth:0];
        [wallpaperController setHomescreenWallpaperScale:scale];
        [_selectionView.backgroundView didAnimate];
    } completion:nil];
    [_zoomAnimator animateToFraction:0.f afterDelay:0.0 withCompletion:^{
        [_zoomAnimator release];
        _zoomAnimator = nil;
        if (completion) {
            completion();
        }
    }];
}

@end
