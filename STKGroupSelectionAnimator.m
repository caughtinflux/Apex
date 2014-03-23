#import "STKGroupSelectionAnimator.h"
#import "STKConstants.h"
#import <SpringBoard/SpringBoard.h>
#import <SpringBoardFoundation/SBFAnimationSettings.h>

@implementation STKGroupSelectionAnimator
{
    STKSelectionView *_selectionView;
    SBIconView *_iconView;
    SBScaleIconZoomAnimator *_zoomAnimator;
    CGRect _startFrame;
    CGRect _endFrame;
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
    SBIconContentView *contentView = [(SBIconController *)[CLASS(SBIconController) sharedInstance] contentView];
    [_selectionView.contentView.subviews[1] setAlpha:0.0f];
    _selectionView.searchTextField.alpha = 0.f;
    _selectionView.layer.cornerRadius = 35.f;
    _selectionView.layer.masksToBounds = YES;
    [contentView addSubview:_selectionView];

    SBRootFolderController *rootFolderController = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _rootFolderController];
    _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:rootFolderController targetIcon:_iconView.icon];    
    _zoomAnimator.settings = [[CLASS(SBPrototypeController) sharedInstance] rootSettings].rootAnimationSettings.folderOpenSettings;
    [_zoomAnimator prepare];

    _startFrame = [_iconView convertRect:[_iconView _iconImageView].frame toView:contentView];
    
    CGSize endSize = [CLASS(SBFolderBackgroundView) folderBackgroundSize];
    CGPoint endOrigin = {(CGRectGetMidX(_selectionView.bounds) - (endSize.width * 0.5f)),
                        (CGRectGetMidY(_selectionView.bounds) - (endSize.height * 0.5f))};
    CGRect selectionContentEndFrame = (CGRect){endOrigin, endSize};

    _endFrame = contentView.bounds;
    _selectionView.frame = _startFrame;
    _selectionView.contentView.frame = _startFrame;

    double duration = _zoomAnimator.settings.outerFolderFadeSettings.duration;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [[CLASS(SBIconController) sharedInstance] currentRootIconList].alpha = 0.f;
        _selectionView.contentView.center = (CGPoint){CGRectGetMidX(_selectionView.bounds), CGRectGetMidY(_selectionView.bounds)};
        _selectionView.contentView.frame = selectionContentEndFrame;
        _selectionView.center = (CGPoint){CGRectGetMidX(contentView.bounds), CGRectGetMidY(contentView.bounds)};
        _selectionView.frame = _endFrame;
        [_selectionView.contentView.subviews[1] setAlpha:1.0f];
        _iconView.alpha = 0.f;
        _selectionView.searchTextField.alpha = 1.f;
    } completion:nil];
    [_zoomAnimator animateToFraction:1.0 afterDelay:0.0 withCompletion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (NSEC_PER_SEC * 0.1)), dispatch_get_main_queue(), ^{
            [_selectionView flashScrollIndicators];
        });
        if (completion) {
            completion();
        }
    }];
}

- (void)closeSelectionViewAnimatedWithCompletion:(STKAnimatorCompletion)completion
{
    _zoomAnimator.settings = [[CLASS(SBPrototypeController) sharedInstance] rootSettings].rootAnimationSettings.folderCloseSettings;
    double duration = _zoomAnimator.settings.outerFolderFadeSettings.duration;
    [UIView animateWithDuration:duration delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        [[CLASS(SBIconController) sharedInstance] currentRootIconList].alpha = 1.f;
        _selectionView.alpha = 0.f;
        _iconView.alpha = 1.f;
    } completion:nil];
    [_zoomAnimator animateToFraction:0.f afterDelay:0 withCompletion:^{
        if (completion) {
            completion();
        }
        [_zoomAnimator release];
        _zoomAnimator = nil;
    }];
}

@end
