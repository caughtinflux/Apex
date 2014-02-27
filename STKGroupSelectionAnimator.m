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
    _selectionView.contentView.alpha = 0.0f;
    _selectionView.layer.cornerRadius = 35.f;
    _selectionView.layer.masksToBounds = YES;
    [contentView addSubview:_selectionView];

    SBRootFolderController *rootFolderController = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _rootFolderController];
    _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:rootFolderController targetIcon:_iconView.icon];    
    _zoomAnimator.settings = [[CLASS(SBPrototypeController) sharedInstance] rootSettings].rootAnimationSettings.folderOpenSettings;
    [_zoomAnimator prepare];

    _startFrame = [_iconView convertRect:[_iconView _iconImageView].frame toView:contentView];
    CGSize endSize = [CLASS(SBFolderBackgroundView) folderBackgroundSize];
    CGPoint endOrigin = {(CGRectGetMidX(contentView.bounds) - (endSize.width * 0.5f)),
                        (CGRectGetMidY(contentView.bounds) - (endSize.height * 0.5f))};
    _endFrame = (CGRect){endOrigin, [CLASS(SBFolderBackgroundView) folderBackgroundSize]};

    _selectionView.frame = _startFrame;

    double duration = _zoomAnimator.settings.outerFolderFadeSettings.duration;
    [UIView animateWithDuration:duration animations:^{
        [[CLASS(SBIconController) sharedInstance] currentRootIconList].alpha = 0.f;
        _selectionView.frame = _endFrame;
        _selectionView.contentView.alpha = 1.f;
        _iconView.alpha = 0.f;
    }];
    [_zoomAnimator animateToFraction:1.0 afterDelay:0.0 withCompletion:^{
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
