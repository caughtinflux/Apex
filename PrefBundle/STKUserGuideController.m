#import "STKUserGuideController.h"
#import "Localization.h"

#define kLabelInset 10.0

@implementation STKUserGuideController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = LOCALIZE(USER_GUIDE);
}

- (id)specifiers
{
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"GuideSpecs" target:self] retain];
    }
    return _specifiers;
}

- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target
{
    id specifiers = [super loadSpecifiersFromPlistName:name target:target];
    for (PSSpecifier *specifier in specifiers) {
        [specifier setName:Localize([specifier name])];
    }
    return specifiers;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(id)indexPath
{
    NSString *text = Localize([[self specifierAtIndex:[self indexForIndexPath:indexPath]] propertyForKey:@"label"]);
    CGFloat cellWidth = CGRectInset(self.view.bounds, kLabelInset, kLabelInset).size.width;
    CGRect bounds = [text boundingRectWithSize:CGSizeMake(cellWidth, CGFLOAT_MAX)
                                       options:NSStringDrawingUsesLineFragmentOrigin
                                    attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16.f]}
                                       context:nil];
    CGSize size = CGSizeMake(bounds.size.width, bounds.size.height + (kLabelInset * 2));
    return size.height;
}

@end

