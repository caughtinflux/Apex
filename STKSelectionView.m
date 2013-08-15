#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "STKSelectionViewCell.h"

#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

@interface STKSelectionView ()
{
    UITableView    *_listTableView;
    NSArray        *_availableAppIcons;
    SBIconModel    *_model;
    SBIconListView *_listView;

    STKLayoutPosition _position;
    STKPositionMask   _mask;
}

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

        NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:@"displayName" ascending:YES];
        [(NSMutableArray *)_availableAppIcons sortUsingDescriptors:@[descriptor]];

        _listTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _listTableView.dataSource = self;
        _listTableView.delegate = self;
        _listTableView.backgroundColor = [UIColor clearColor];
        _listTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        [_listTableView registerClass:[STKSelectionViewCell class] forCellReuseIdentifier:CellIdentifier];

        [self addSubview:_listTableView];

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
    [_listTableView release];

    [super dealloc];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGPoint iconOrigin = [_listView convertPoint:_selectedView.frame.origin fromView:_centralView];
    CGSize defaultIconImageSize = [[_selectedView class] defaultIconImageSize];
    CGSize maxLabelSize = [[_selectedView class] _maxLabelSize];

    CGRect frame = (CGRect){{iconOrigin.x, 0}, {(defaultIconImageSize.width + 5 + maxLabelSize.width), [UIScreen mainScreen].bounds.size.height}};
    self.frame = frame;

    _listTableView.frame = (CGRect){CGRectZero.origin, frame.size};
}

#pragma mark - UITableView Data Source
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

#pragma mark - Header/Footer Methods
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    return [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
}

@end
