#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "STKSelectionViewCell.h"

#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

#define PTOS NSStringFromCGPoint
#define RTOS NSStringFromCGRect

@interface STKSelectionView ()
{
    UITableView       *_listTableView;
    NSArray           *_availableAppIcons;
    SBIconModel       *_model;
    SBIconListView    *_listView;

    STKLayoutPosition  _position;
    STKPositionMask    _mask;

    UIImageView       *_highlightView;
    NSIndexPath       *_indexPathToSelect;
}

- (void)_findAndHighlightSelection;

/**
    @param icon: The icon for which is index path is to be found
    @returns: NSIndexPath instance containing info about `icon` in _listTableView, or nil if it couldn't be found
*/
- (NSIndexPath *)_indexPathForIcon:(SBIcon *)icon;
- (void)_setHidesHighlight:(BOOL)hide;

@end

static NSString * const CellIdentifier = @"STKIconCell";

@implementation STKSelectionView

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
        BOOL found = NO;
        for (id ident in [_model visibleIconIdentifiers]) {
            if (!found && [ident isEqual:_centralView.icon.leafIdentifier]) {
                continue;
            }
            [(NSMutableArray *)_availableAppIcons addObject:[_model expectedIconForDisplayIdentifier:ident]];
        }

        if (![_selectedView.icon isPlaceholder]) {
            // The selected icon view's icon will not be in the model's visible app IDs. Make sure we add it, and then scroll to it.
            // Do it only if the icon is an actual app icon
            [(NSMutableArray *)_availableAppIcons addObject:_selectedView.icon];
        }

        NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:@"displayName" ascending:YES];
        [(NSMutableArray *)_availableAppIcons sortUsingDescriptors:@[descriptor]];

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
            iv.alpha = (iv.icon.isPlaceholder? 0.8 : 0.2f);
        });

        [self setNeedsLayout];
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
    [_selectedView release];
    [_centralView release];
    [_iconViewsLayout release];
    [_availableAppIcons release];
    [_highlightView release];
    [_listTableView release];

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
    _highlightView.center = [self convertPoint:_selectedView.iconImageView.center fromView:_selectedView];

    _listTableView.contentInset = UIEdgeInsetsMake(ABS(iconOrigin.y - _listTableView.frame.origin.y), 0, ABS(iconLowerEdge.y - _listTableView.frame.size.height), 0);
}

- (void)scrollToDefault
{
    if ([_selectedView.icon isPlaceholder]) {
        return;
    }

    [UIView animateWithDuration:0.2 animations:^{
        [_listTableView scrollToRowAtIndexPath:[self _indexPathForIcon:_selectedView.icon] atScrollPosition:UITableViewScrollPositionTop animated:NO];
        [self _setHidesHighlight:NO];
    }];
}

#pragma mark - Private Methods
#define R_AREA(_r2 /* D2! */)  _r2.size.width * _r2.size.height
- (void)_findAndHighlightSelection
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
        [UIView animateWithDuration:0.2f animations:^{
            [_listTableView scrollToRowAtIndexPath:indexToSelect atScrollPosition:UITableViewScrollPositionTop animated:NO];
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


#pragma mark - Delegates, DataSources etc.
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self _setHidesHighlight:YES];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate) {
        [self _findAndHighlightSelection];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self _findAndHighlightSelection];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    [self _findAndHighlightSelection];
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

@end
