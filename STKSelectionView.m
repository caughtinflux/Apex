#import "STKSelectionView.h"
#import "STKConstants.h"
#import "STKIconLayout.h"
#import "STKIconLayoutHandler.h"
#import "STKSelectionViewCell.h"

#import <SpringBoard/SpringBoard.h>
#import <AppList/AppList.h>

@interface STKSelectionView ()
{
    UITableView *_listTableView;
    NSArray     *_availableAppIdentifiers;
    SBIconModel *_model;

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
        _availableAppIdentifiers = [NSMutableArray array];

        _model = [[objc_getClass("SBIconController") sharedInstance] model];
        BOOL found = NO;
        for (id *ident in [_model visibleIconIdentifiers]) {
            if (!found && [ident isEqual:_centralView.leafIdentifier]) {
                continue;
            }
            [_availableAppIdentifiers addObject:ident];
        }

        CGRect frame = CGRectZero;
        _listTableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStylePlain];
        _listTableView.dataSource = self;
        _listTableView.delegate = self;
        [_listTableView registerClass:[STKSelectionViewCell class] forCellReuseIdentifier:CellIdentifier];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    NSAssert(NO, @"***You must use the designated initializer");
    return nil;
}


#pragma mark - UITableView Data Source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _availableAppIdentifiers.count;
}

- (STKSelectionViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    STKSelectionViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
    cell.icon = [_model expectedIconForDisplayIdentifier:_availableAppIdentifiers[indexPath.row - 1]];
    
    return cell;
}

@end
