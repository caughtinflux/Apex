#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "STKSelectionViewCell.h"

#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>

@interface STKSelectionView ()
{
    UITableView *_listTableView;
    NSArray     *_availableAppIcons;
    SBIconModel *_model;

    STKLayoutPosition _position;
    STKPositionMask   _mask;
}

@end

static NSString * const CellIdentifier = @"STKIconCell";

@implementation STKSelectionView

- (instancetype)initWithIconView:(SBIconView *)iconView inLayout:(STKIconLayout *)iconViewLayout position:(STKPositionMask)position centralIconView:(SBIconView *)centralIconView displacedIcons:(STKIconLayout *)displacedIconsLayout
{
    if ((self = [super initWithFrame:CGRectMake(0, 0, 75, 300)])) {
        _selectedView = [iconView retain];
        _centralView = [centralIconView retain];
        _mask = position;
        _position = [iconViewLayout positionForIcon:iconView];
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

        CGRect frame = CGRectMake(0, 0, 150, 300);
        _listTableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStylePlain];
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
    return [objc_getClass("SBIconView") defaultIconImageSize].height + 10;
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
