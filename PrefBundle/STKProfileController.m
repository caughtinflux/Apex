#import "STKProfileController.h"
#import "Localization.h"
#import "../STKConstants.h"
#import <Preferences/PSSpecifier.h>

#define TEXT_COLOR [UIColor colorWithRed:76/255.0f green:86/255.0f blue:106/255.0f alpha:1.0f]
#define TEXT_LARGE_FONT [UIFont fontWithName:@"HelveticaNeue" size:72.0f]
#define TEXT_FONT [UIFont fontWithName:@"HelveticaNeue" size:15.0f]

#define TEXT_SHADOW_OFFSET CGSizeMake(0, 1)
#define TEXT_SHADOW_COLOR [UIColor whiteColor]

static NSString * const ProfileCellReuseIdentifier = @"Profile";
static NSString * const RegularCellReuseIdentifier = @"Cell";

@implementation STKProfileController
{
    long _year;
}

- (id)initForContentSize:(CGSize)size
{    
    if ((self = [super init])) {   
        _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
        [_tableView setDataSource:self];
        [_tableView setDelegate:self];
        [_tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin];
        [self.view addSubview:_tableView];
        [_tableView registerClass:[STKTableViewCellProfile class] forCellReuseIdentifier:ProfileCellReuseIdentifier];
        [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:RegularCellReuseIdentifier];

        NSDate *date = [NSDate date];
        NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        NSDateComponents *components = [gregorian components:NSYearCalendarUnit fromDate:date];
        _year = (long)[components year];
    }
    return self;
}

- (void)dealloc
{
    [_tableView setDelegate:nil];
    [_tableView setDataSource:nil];
    [_tableView release];
    [super dealloc];
}

- (UITableView *)table
{
    return _tableView;
}

- (CGSize)contentSize
{
    return [_tableView frame].size;
}

- (id)navigationTitle
{
    return LOCALIZE(THE_CREATORS);
}

- (NSString *)title
{
    return LOCALIZE(THE_CREATORS);
}

- (NSMutableDictionary *)preferences
{
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{    
    return 3;
}

- (id)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{    
    return 1;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *handleString;
    switch (indexPath.section) {
        case 0:
            handleString = @"Sentry_NC";
            break;
        case 1:
            handleString = @"caughtinflux";
            break;
        case 2:
            handleString = @"A3tweaks";
            break;
        default:
            return;
    }
    UIApplication *app = [UIApplication sharedApplication];

    NSURL *twitterific = [NSURL URLWithString:[@"twitterrific:///profile?screen_name=" stringByAppendingString:handleString]];
    NSURL *tweetbot = [NSURL URLWithString:[@"tweetbot:///user_profile/" stringByAppendingString:handleString]];
    NSURL *twitterApp = [NSURL URLWithString:[@"twitter:///user?screen_name=" stringByAppendingString:handleString]];
    if ([app canOpenURL:tweetbot]) {
        [app openURL:tweetbot];
    }
    else if ([app canOpenURL:twitterific]) {
        [app openURL:twitterific];
    }
    else if ([app canOpenURL:twitterApp])
            [app openURL:twitterApp];
    else {
        [app openURL:[NSURL URLWithString:[@"http://twitter.com/" stringByAppendingString:handleString]]];
    }
}

- (id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger section = indexPath.section;
    NSString *reuseIdentifier = section < 2 ? ProfileCellReuseIdentifier : RegularCellReuseIdentifier;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier forIndexPath:indexPath];    
    switch (section) {
        case 0:
            [((STKTableViewCellProfile *)cell) loadImage:@"Sentry" nameText:LOCALIZE(SENTRY) handleText:LOCALIZE(SENTRY_HANDLE) infoText:LOCALIZE(SENTRY_INFO)];
            break;
        case 1:
            [((STKTableViewCellProfile *)cell) loadImage:@"Aditya_KD" nameText:LOCALIZE(ADITYA_KD) handleText:LOCALIZE(ADITYA_KD_HANDLE) infoText:LOCALIZE(ADITYA_KD_INFO)];
            break;
        case 2:
            cell.textLabel.text = LOCALIZE(FOLLOW_A3TWEAKS);
            cell.imageView.image = [[STKPrefsHelper sharedHelper] ownImageNamed:@"GroupLogo"];
            break;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section < 2) return 106.0f;
    else return 44.0f;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch (section) {
        default:
            return nil;
        case 2:
            return [NSString stringWithFormat:LOCALIZE(COPYRIGHT_TEXT), _year];
    }
}

@end
