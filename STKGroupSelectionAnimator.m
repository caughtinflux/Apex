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
    _selectionView.iconCollectionView.alpha = 0.0f;
    _selectionView.searchTextField.alpha = 0.f;
    _selectionView.frame = iconContentView.bounds;
    [iconContentView addSubview:_selectionView];

    SBFolderController *currentFolderController = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _currentFolderController];
    _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:currentFolderController targetIcon:_iconView.icon];    
    _zoomAnimator.settings = [[CLASS(SBPrototypeController) sharedInstance] rootSettings].rootAnimationSettings.folderOpenSettings;
    [_zoomAnimator prepare];
    
    CGSize endSize = [CLASS(SBFolderBackgroundView) folderBackgroundSize];
    CGFloat startScale = ([_iconView _iconImageView].frame.size.width / endSize.width);
    _selectionView.contentView.bounds = (CGRect){CGPointZero, endSize};
    _selectionView.contentView.transform = CGAffineTransformMakeScale(startScale, startScale);
    _selectionView.iconCollectionView.frame = _selectionView.contentView.bounds;
    [_selectionView scrollToSelectedIconAnimated:NO];

    CGPoint startCenter = [_selectionView convertPoint:[_iconView iconImageCenter] fromView:_iconView];
    _selectionView.contentView.center = startCenter;

    double duration = _zoomAnimator.settings.outerFolderFadeSettings.duration;
    [UIView animateWithDuration:duration delay:0 options:0 animations:^{
        _selectionView.contentView.transform = CGAffineTransformMakeScale(1.0, 1.0);
        _selectionView.contentView.center = (CGPoint){CGRectGetMidX(_selectionView.bounds), CGRectGetMidY(_selectionView.bounds)};

        STKCurrentListView().alpha = 0.f;
        [[CLASS(SBIconController) sharedInstance] dockListView].alpha = 0.f;
        _selectionView.iconCollectionView.alpha = 1.0f;
        _iconView.alpha = 0.f;
        _selectionView.searchTextField.alpha = 1.f;
    } completion:nil];
    [UIView animateWithDuration:duration delay:0.0 options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        SBWallpaperController *wallpaperController = [CLASS(SBWallpaperController) sharedInstance];
        CGFloat scale = [CLASS(SBFolderController) wallpaperScaleForDepth:1];
        [wallpaperController setHomescreenWallpaperScale:scale];
    } completion:nil];
    [_zoomAnimator animateToFraction:1.0 afterDelay:0.0 withCompletion:^{
        [_selectionView flashScrollIndicators];
        if (completion) {
            completion();
        }
    }];
}

- (void)closeSelectionViewAnimatedWithCompletion:(STKAnimatorCompletion)completion
{
    _zoomAnimator.settings = [[CLASS(SBPrototypeController) sharedInstance] rootSettings].rootAnimationSettings.folderCloseSettings;
    double duration = _zoomAnimator.settings.outerFolderFadeSettings.duration;

    [UIView animateWithDuration:duration delay:0.0 options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        _iconView.alpha = 1.f;
        _selectionView.alpha = 0.f;
        STKCurrentListView().alpha = 1.f;
        [[CLASS(SBIconController) sharedInstance] dockListView].alpha = 1.f;
    } completion:nil];
    [UIView animateWithDuration:(duration + 0.4) delay:0.0 options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        SBWallpaperController *wallpaperController = [CLASS(SBWallpaperController) sharedInstance];
        CGFloat scale = [CLASS(SBFolderController) wallpaperScaleForDepth:0];
        [wallpaperController setHomescreenWallpaperScale:scale];
    } completion:nil];
    [_zoomAnimator animateToFraction:0.f afterDelay:0.05 withCompletion:^{
        [_zoomAnimator release];
        _zoomAnimator = nil;
        if (completion) {
            completion();
        }
    }];
}

@end
