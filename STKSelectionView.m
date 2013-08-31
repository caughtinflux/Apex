#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "STKSelectionViewCell.h"
#import "STKPlaceHolderIcon.h"
#import "STKPreferences.h"

#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

#define PTOS NSStringFromCGPoint
#define RTOS NSStringFromCGRect

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@interface STKSelectionView ()
{
    UITableView       *_listTableView;
    NSMutableArray    *_availableAppIcons;
    SBIconModel       *_model;
    SBIconListView    *_listView;

    STKLayoutPosition  _position;
    STKPositionMask    _mask;

    UIImageView       *_highlightView;
    NSIndexPath       *_indexPathToSelect;

    SBIcon            *_highlightedIcon;
    UIButton          *_doneButton;
    BOOL               _displayingDoneButton;
}

- (void)_scrollToNearest;

/**
    @param icon: The icon for which is index path is to be found
    @returns: NSIndexPath instance containing info about `icon` in _listTableView, or nil if it couldn't be found
*/
- (NSIndexPath *)_indexPathForIcon:(SBIcon *)icon;
- (void)_setHidesHighlight:(BOOL)hide;

- (void)_showDoneButton;
- (void)_hideDoneButton;
- (void)_doneButtonTapped:(UIButton *)button;

@end
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static NSString * const CellIdentifier = @"STKIconCell";

@implementation STKSelectionView

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (instancetype)initWithIconView:(SBIconView *)iconView inLayout:(STKIconLayout *)iconViewLayout position:(STKPositionMask)position centralIconView:(SBIconView *)centralIconView displacedIcons:(STKIconLayout *)displacedIconsLayout
{
    if ((self = [super initWithFrame:CGRectZero])) {
        _selectedView = [iconView retain];
        _centralView = [centralIconView retain];
        _iconViewsLayout = [iconViewLayout retain];
        _mask = position;
        _position = [iconViewLayout positionForIcon:iconView];
        _listView = STKListViewForIcon(_centralView.icon);
        _model = (SBIconModel *)[[objc_getClass("SBIconController") sharedInstance] model];

        _availableAppIcons = [NSMutableArray new];
        
        for (id ident in [_model visibleIconIdentifiers]) {
            // Icons in a stack are already removed from -[SBIconModel visibleIconIdentifiers]
            // Now we need to nemove the central and other icons with stacks
            if (ICONID_HAS_STACK(ident) || [ident isEqual:_centralView.icon.leafIdentifier]) {
                continue;
            }
            [_availableAppIcons addObject:[_model expectedIconForDisplayIdentifier:ident]];
        }

        // The selected icon view's icon will not be in the model's visible app IDs, so add it.
        [_availableAppIcons addObject:_selectedView.icon];

        if (!_selectedView.icon.isPlaceholder) {
            // Add a placeholder to available icons so the user can have a "None"-like option
            STKPlaceHolderIcon *ph = [[[objc_getClass("STKPlaceHolderIcon") alloc] init] autorelease];
            [_availableAppIcons addObject:ph];
        }

        NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:@"displayName" ascending:YES selector:@selector(caseInsensitiveCompare:)];
        [_availableAppIcons sortUsingDescriptors:@[descriptor]];

        _listTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _listTableView.dataSource = self;
        _listTableView.delegate = self;
        _listTableView.backgroundColor = [UIColor clearColor];
        _listTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        [_listTableView registerClass:[STKSelectionViewCell class] forCellReuseIdentifier:CellIdentifier];

        [self addSubview:_listTableView];

        _highlightView = [[UIImageView alloc] initWithImage:UIIMAGE_NAMED(@"SelectionHighlight")];
        _highlightView.alpha = 0.f;
        [self insertSubview:_highlightView belowSubview:_listTableView];

        _selectedView.alpha = 0.f;
        _centralView.alpha = 0.2;
        MAP([_iconViewsLayout allIcons], ^(SBIconView *iv) {
            if (iv == _selectedView) {
                return;
            }
            iv.alpha = (iv.icon.isPlaceholder ? 0.8 : 0.2f);
        });


        _doneButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_doneButton setImage:UIIMAGE_NAMED(@"CheckButton") forState:UIControlStateNormal];
        [_doneButton addTarget:self action:@selector(_doneButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        _doneButton.frame = (CGRect){ CGPointZero, [UIIMAGE_NAMED(@"CheckButton") size] };
        _doneButton.tag = 4321;

        [self setNeedsLayout];
        [self _setHidesHighlight:NO];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    NSAssert(NO, @"***You must use the designated initializer");
    return nil;
}

- (void)dealloc
{
    _listTableView.delegate = nil;
    _listTableView.dataSource = nil;

    [_selectedView release];
    _selectedView = nil;
    
    [_centralView release];
    _centralView = nil;

    [_iconViewsLayout release];

    [_availableAppIcons release];
    _availableAppIcons = nil;

    [_highlightView removeFromSuperview];
    [_highlightView release];
    _highlightView = nil;

    [_doneButton removeFromSuperview];
    [_doneButton release];
    _doneButton = nil;

    [_listTableView removeFromSuperview];
    [_listTableView release];
    _listTableView = nil;

    [super dealloc];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGPoint iconOrigin = [self.superview convertPoint:_selectedView.frame.origin fromView:_selectedView.superview];
    CGPoint iconLowerEdge = (CGPoint){iconOrigin.x, (iconOrigin.y + _selectedView.frame.size.height)};

    CGSize defaultIconImageSize = [[_selectedView class] defaultIconImageSize];
    CGSize maxLabelSize = [[_selectedView class] _maxLabelSize];

    CGRect frame = (CGRect){{iconOrigin.x - 3, 0}, {(defaultIconImageSize.width + 5 + maxLabelSize.width), [UIScreen mainScreen].bounds.size.height}};
    self.frame = frame;

    _listTableView.frame = (CGRect){{self.bounds.origin.x + 3, self.bounds.origin.y}, frame.size};
    _listTableView.contentInset = UIEdgeInsetsMake(ABS(iconOrigin.y - _listTableView.frame.origin.y), 0, ABS(iconLowerEdge.y - _listTableView.frame.size.height), 0);

    CGPoint highlightCenter = [self convertPoint:_selectedView.iconImageView.center fromView:_selectedView];
    _highlightView.center = (CGPoint){ highlightCenter.x, highlightCenter.y - 1 };
}
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)scrollToDefaultAnimated:(BOOL)animated
{
    NSIndexPath *ip = ^{
        if ([_selectedView.icon isPlaceholder]) {
            return [NSIndexPath indexPathForRow:0 inSection:0];
        }

        return [self _indexPathForIcon:_selectedView.icon];
    }();
    
    [_listTableView selectRowAtIndexPath:ip animated:animated scrollPosition:UITableViewScrollPositionTop];
    [self _setHidesHighlight:NO];
    [self _showDoneButton];
}

- (void)moveToIconView:(SBIconView *)iconView animated:(BOOL)animated completion:(void(^)(void))completionBlock
{
    [_selectedView release];
    _selectedView = [iconView retain];
    
    [UIView animateWithDuration:(animated ? 0.2f : 0.0f) animations:^{
        [self layoutSubviews];
    } completion:^(BOOL done) {
        if (done && completionBlock) {
            completionBlock();
        }
    }];
}

- (void)prepareForRemoval
{
    _centralView.alpha = 1.f;
    MAP([_iconViewsLayout allIcons], ^(SBIconView *iv) {
        iv.alpha = 1.f;
    });
}

- (SBIcon *)highlightedIcon
{
    return _availableAppIcons[[_listTableView indexPathForSelectedRow].row];
}
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#define R_AREA(_r2 /* D2! */)  _r2.size.width * _r2.size.height
- (void)_scrollToNearest
{
    CGRect rect = [self convertRect:_highlightView.frame toView:_listTableView];
    NSArray *ips = [_listTableView indexPathsForRowsInRect:rect];

    NSIndexPath *indexToSelect = ^NSIndexPath * (void) {
        if (!ips || ips.count == 0) {
            return nil;
        }
        if (ips.count == 1) {
            return ips[0];
        }

        CGRect higlightFrame = [self convertRect:_highlightView.frame toView:_listTableView];
        CGRect frame1 = [_listTableView rectForRowAtIndexPath:ips[0]];
        CGRect frame2 = [_listTableView rectForRowAtIndexPath:ips[1]];

        CGRect intersec1, intersec2;
        intersec1 = CGRectIntersection(frame1, higlightFrame);
        intersec2 = CGRectIntersection(frame2, higlightFrame);

        if (R_AREA(intersec1) >= R_AREA(intersec2)) {
            return ips[0];
        }

        return ips[1];
    }();
    
    if (indexToSelect) {
        [UIView animateWithDuration:0.29f animations:^{
            [_listTableView selectRowAtIndexPath:indexToSelect animated:YES scrollPosition:UITableViewScrollPositionTop];
            [self _setHidesHighlight:NO];
        }];
    }
}

- (NSIndexPath *)_indexPathForIcon:(id)icon
{
    NSUInteger idx = [_availableAppIcons indexOfObject:icon];
    if (idx == NSNotFound) {
        return nil;
    }
    return [NSIndexPath indexPathForRow:idx inSection:0];
}

- (void)_setHidesHighlight:(BOOL)hide
{
    _highlightView.alpha = (hide ? 0.f : 1.f);
}

- (void)_iconTapped:(UITapGestureRecognizer *)gr
{
    NSIndexPath *ip = objc_getAssociatedObject(gr, @selector(indexPath));
    [_listTableView selectRowAtIndexPath:ip animated:YES scrollPosition:UITableViewScrollPositionTop];
}

- (void)_showDoneButton;
{  
    if (_displayingDoneButton) {
        return;
    }
    STKSelectionViewCell *cell = (STKSelectionViewCell *)[_listTableView cellForRowAtIndexPath:[_listTableView indexPathForSelectedRow]];
    SBIconView *iconView = cell.iconView;
    _doneButton.center = (CGPoint){ CGRectGetMaxX(iconView.iconImageView.frame), CGRectGetMinY(iconView.iconImageView.frame) + 2 };
    cell.hitTestOverrideSubviewTag = 4321;
    [iconView addSubview:_doneButton];
    _displayingDoneButton = YES;
}

- (void)_hideDoneButton;
{
    [(STKSelectionViewCell *)_doneButton.superview.superview setHitTestOverrideSubviewTag:0];
    [_doneButton removeFromSuperview];
    _displayingDoneButton = NO;
}

- (void)_doneButtonTapped:(UIButton *)button
{
    if ([_delegate respondsToSelector:@selector(closeButtonTappedOnSelectionView:)]) {
        [_delegate closeButtonTappedOnSelectionView:self];
    }
}
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Delegates, DataSources etc.
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate) {
        [self _scrollToNearest];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{   
    [self _scrollToNearest];
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView
{
    [self _scrollToNearest];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self _hideDoneButton];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    [self _showDoneButton];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    // We need to set up our own recognizers, so that taps on cells outside of the content inset will be picked up too
    cell = (STKSelectionViewCell *)cell;
    UITapGestureRecognizer *gr = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_iconTapped:)] autorelease];
    [cell addGestureRecognizer:gr];

    // Associate the index path with gr, so the -_iconTapped: can get it back from the recognizer
    objc_setAssociatedObject(gr, @selector(indexPath), indexPath, OBJC_ASSOCIATION_RETAIN);
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    cell = (STKSelectionViewCell *)cell;

    id recognizer = cell.gestureRecognizers[0];
    objc_removeAssociatedObjects(recognizer);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _availableAppIcons.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [objc_getClass("SBIconView") defaultIconImageSize].height + [_listView verticalIconPadding] - 3;
}

- (STKSelectionViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    STKSelectionViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
    cell.icon = _availableAppIcons[indexPath.row];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    return [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
}
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@end
