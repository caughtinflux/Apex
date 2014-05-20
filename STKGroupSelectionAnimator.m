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
    _selectionView.contentView.alpha = 0.0;
    _selectionView.searchTextField.alpha = 0.0;
    _selectionView.frame = iconContentView.bounds;
    [iconContentView addSubview:_selectionView];

    SBFolderController *currentFolderController = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _currentFolderController];
    SBPrototypeController *protoController = [CLASS(SBPrototypeController) sharedInstance];
    _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:currentFolderController targetIcon:_iconView.icon];    
    _zoomAnimator.settings = [protoController rootSettings].rootAnimationSettings.folderOpenSettings;
    [_zoomAnimator prepare];
    
    CGSize endSize = [CLASS(SBFolderBackgroundView) folderBackgroundSize];
    _startScale = ([_iconView _iconImageView].frame.size.width / endSize.width);
    _selectionView.contentView.bounds = (CGRect){CGPointZero, endSize};
    _selectionView.contentView.transform = CGAffineTransformMakeScale(_startScale, _startScale);
    _selectionView.iconCollectionView.frame = _selectionView.contentView.bounds;
    [_selectionView scrollToSelectedIconAnimated:NO];

    _startCenter = [_selectionView convertPoint:[_iconView iconImageCenter] fromView:_iconView];
    _selectionView.contentView.center = _startCenter;

    NSTimeInterval duration = _zoomAnimator.settings.crossfadeSettings.duration;
    if (protoController.rootSettings.animationSettings.slowAnimations) {
        duration *= [protoController rootSettings].animationSettings.slowDownFactor;
    }
    [UIView animateWithDuration:(duration + 0.1) delay:(duration * 0.1) options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        _selectionView.contentView.transform = CGAffineTransformIdentity;
        _selectionView.contentView.center = (CGPoint){CGRectGetMidX(_selectionView.bounds), CGRectGetMidY(_selectionView.bounds)};
        
        STKCurrentListView().alpha = 0.0;
        [[CLASS(SBIconController) sharedInstance] dockListView].alpha = 0.0;
        _selectionView.contentView.alpha = 1.0;
        _selectionView.searchTextField.alpha = 1.0;

        SBWallpaperController *wallpaperController = [CLASS(SBWallpaperController) sharedInstance];
        CGFloat scale = [CLASS(SBFolderController) wallpaperScaleForDepth:1];
        [wallpaperController setHomescreenWallpaperScale:scale];
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
    SBPrototypeController *protoController = [CLASS(SBPrototypeController) sharedInstance];
    _zoomAnimator.settings = [protoController rootSettings].rootAnimationSettings.folderCloseSettings;
    NSTimeInterval duration = _zoomAnimator.settings.crossfadeSettings.duration;
    if (protoController.rootSettings.animationSettings.slowAnimations) {
        duration *= [protoController rootSettings].animationSettings.slowDownFactor;
    }
    [UIView animateWithDuration:duration delay:0.0 options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        _selectionView.searchTextField.alpha = 0.0;
        _selectionView.iconCollectionView.alpha = 0.0;
    } completion:nil];
    [UIView animateWithDuration:(duration + 0.1) delay:(duration * 0.1) options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut) animations:^{
        CGAffineTransform scalingTransform = CGAffineTransformMakeScale(_startScale, _startScale);
        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation((_startCenter.x - _selectionView.contentView.center.x),
                                                                                  (_startCenter.y - _selectionView.contentView.center.y));
        CGAffineTransform finalTransform = CGAffineTransformConcat(scalingTransform, translationTransform);
        _selectionView.contentView.transform = finalTransform;
        
        _selectionView.backgroundView.alpha = 0.0;
        STKCurrentListView().alpha = 1.0;
        [[CLASS(SBIconController) sharedInstance] dockListView].alpha = 1.0;

        SBWallpaperController *wallpaperController = [CLASS(SBWallpaperController) sharedInstance];
        CGFloat scale = [CLASS(SBFolderController) wallpaperScaleForDepth:0];
        [wallpaperController setHomescreenWallpaperScale:scale];
    } completion:nil];
    [_zoomAnimator animateToFraction:0.0 afterDelay:0.0 withCompletion:^{
        [_zoomAnimator release];
        _zoomAnimator = nil;
        if (completion) {
            completion();
        }
    }];
}

@end
