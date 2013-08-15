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
        _mask = position;
        _position = [iconViewLayout positionForIcon:iconView];
        _listView = STKListViewForIcon(_centralView.icon);
        _model = (SBIconModel *)[[objc_getClass("SBIconController") sharedInstance] model];
        
        CGPoint iconOrigin = [_listView convertPoint:_selectedView.frame.origin fromView:_centralView];
        CGSize defaultIconImageSize = [[_selectedView class] defaultIconImageSize];
        CGSize maxLabelSize = [[_selectedView class] _maxLabelSize];

        CGRect frame = (CGRect){{iconOrigin.x, [_listView originForIconAtX:0 Y:0].y}, {(defaultIconImageSize.width + 5 + maxLabelSize.width), _listView.bounds.size.height + 25}};
        self.frame = frame;

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

        _listTableView = [[UITableView alloc] initWithFrame:(CGRect){CGRectZero.origin, frame.size} style:UITableViewStylePlain];
        _listTableView.dataSource = self;
        _listTableView.delegate = self;
        _listTableView.backgroundColor = [UIColor clearColor];
        _listTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        [_listTableView registerClass:[STKSelectionViewCell class] forCellReuseIdentifier:CellIdentifier];

        [self addSubview:_listTableView];
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
    [_availableAppIcons release];
    [_listTableView release];

    [super dealloc];
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
