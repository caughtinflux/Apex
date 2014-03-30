#import "STKGroupSelectionAnimator.h"
#import "STKConstants.h"
#import <SpringBoard/SpringBoard.h>
#import <SpringBoardFoundation/SBFAnimationSettings.h>

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

    SBRootFolderController *rootFolderController = [(SBIconController *)[CLASS(SBIconController) sharedInstance] _rootFolderController];
    _zoomAnimator = [[CLASS(SBScaleIconZoomAnimator) alloc] initWithFolderController:rootFolderController targetIcon:_iconView.icon];    
    _zoomAnimator.settings = [[CLASS(SBPrototypeController) sharedInstance] rootSettings].rootAnimationSettings.folderOpenSettings;
    [_zoomAnimator prepare];
    
    CGSize endSize = [CLASS(SBFolderBackgroundView) folderBackgroundSize];
    CGPoint endOrigin = {(CGRectGetMidX(_selectionView.bounds) - (endSize.width * 0.5f)),
                         (CGRectGetMidY(_selectionView.bounds) - (endSize.height * 0.5f))};
    CGRect selectionContentEndFrame = (CGRect){endOrigin, endSize};

    CGRect startFrame = [_selectionView convertRect:[_iconView iconImageFrame] fromView:_iconView];
    CGSize imageSize = [_iconView iconImageVisibleSize];
    startFrame.origin.y -= (imageSize.height * 0.5);
    startFrame.origin.x -= (imageSize.width * 0.5);
    _selectionView.contentView.frame = startFrame;

    [[CLASS(SBIconController) sharedInstance] currentRootIconList].alpha = 0.f;
    CGFloat startScale = ([_iconView _iconImageView].frame.size.width / endSize.width);
    _selectionView.contentView.transform = CGAffineTransformMakeScale(startScale, startScale);

    double duration = _zoomAnimator.settings.outerFolderFadeSettings.duration;
    [UIView animateWithDuration:duration delay:0 options:0 animations:^{
        _selectionView.contentView.transform = CGAffineTransformMakeScale(1.0, 1.0);
        _selectionView.contentView.frame = selectionContentEndFrame;
        [[CLASS(SBIconController) sharedInstance] currentRootIconList].alpha = 0.f;
        _selectionView.iconCollectionView.alpha = 1.0f;
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
        STKGroupView *groupView = [_iconView containerGroupView];
        SBIconListView *listView = STKListViewForIcon(groupView.group.centralIcon);
        listView.stk_modifyDisplacedIconOrigin = YES;
        [_zoomAnimator cleanup];
        listView.stk_modifyDisplacedIconOrigin = NO;
        [_zoomAnimator release];
        _zoomAnimator = nil;
        if (completion) {
            completion();
        }
    }];
}

@end
