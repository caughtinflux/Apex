#import "STKPrefsController.h"
#import "STKProfileController.h"
#import "Localization.h"
#import "Globals.h"
#import "../STKConstants.h"

#define TEXT_COLOR [UIColor colorWithRed:76/255.0f green:86/255.0f blue:106/255.0f alpha:1.0f]
#define TEXT_LARGE_FONT [UIFont fontWithName:@"HelveticaNeue" size:72.0f]
#define TEXT_FONT [UIFont fontWithName:@"HelveticaNeue" size:15.0f]

#define TEXT_SHADOW_OFFSET CGSizeMake(0, 1)
#define TEXT_SHADOW_COLOR [UIColor whiteColor]

static NSString * const PreviewSpecifierID = @"SHOW_PREVIEW";
static NSString * const NotchesSpecifierID = @"HIDE_NOTCHES";

@implementation STKPrefsController

- (id)initForContentSize:(CGSize)size
{
    if ([PSViewController instancesRespondToSelector:@selector(initForContentSize:)])
        self = [super initForContentSize:size];
    else
        self = [super init];
    
    if (self) {
        NSBundle *bundle = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/ApexSettings.bundle"];
        UIImage *image = [UIImage imageNamed:@"GroupLogo.png" inBundle:bundle];
        UINavigationItem *item = self.navigationItem;
        item.titleView = [[[UIImageView alloc] initWithImage:image] autorelease];
        
        UIImage *heart = [UIImage imageNamed:@"Heart.png" inBundle:bundle];
        UIButton *buttonView = [[[UIButton alloc] initWithFrame:(CGRect){CGPointZero, {heart.size.width + 12, heart.size.height}}] autorelease];
        [buttonView setImage:heart forState:UIControlStateNormal];
        [buttonView addTarget:self action:@selector(showHeartDialog) forControlEvents:UIControlEventTouchUpInside];
        UIBarButtonItem *button = [[[UIBarButtonItem alloc] initWithCustomView:buttonView] autorelease];
        item.rightBarButtonItem = button;
    }
    return self;
}

- (id)specifiers
{
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"ApexSettings" target:self] retain];
    }
    return _specifiers;
}

- (NSArray *)loadSpecifiersFromPlistName:(NSString *)plistName target:(id)target
{
    // Always make the target self so that things will resolve properly
    NSArray *result = [super loadSpecifiersFromPlistName:plistName target:self];

#ifdef DEBUG
    NSMutableArray *newSpecs = [[result mutableCopy] autorelease];
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:@"Delete Preferences" target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];
    spec->action = @selector(__deletePreferences);
    [newSpecs addObject:spec];
    result = newSpecs;
#endif

    BOOL shouldAdd = NO;
    for (PSSpecifier *specifier in result) {
        [specifier setName:Localize([specifier name])];
        NSString *footerText = [specifier propertyForKey:@"footerText"];
        if ([footerText isKindOfClass:[NSString class]]) {
            [specifier setProperty:Localize(footerText) forKey:@"footerText"];
        }

        if (!shouldAdd) {
            shouldAdd = ([[specifier identifier] isEqualToString:PreviewSpecifierID] && ([[self readPreferenceValue:specifier] boolValue] == NO));
        }
    }

    if (shouldAdd) {
        result = [[result mutableCopy] autorelease];
        [(NSMutableArray *)result insertObject:[self _notchSpecifier] atIndex:3];
    }

    return result;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
    [super setPreferenceValue:value specifier:specifier];

    if ([[specifier identifier] isEqual:PreviewSpecifierID]) {
        
        PSSpecifier *notchSpecifier = [self specifierForID:NotchesSpecifierID];

        BOOL shouldAdd = (([[self readPreferenceValue:specifier] boolValue] == NO) && !notchSpecifier);
        if (shouldAdd) {
            PSSpecifier *hideGrabberSpecifier = [self _notchSpecifier];
            [self insertSpecifier:hideGrabberSpecifier afterSpecifierID:PreviewSpecifierID animated:YES];
        }
        else if ([[self readPreferenceValue:specifier] boolValue] && notchSpecifier) {
            [self removeSpecifierID:[notchSpecifier identifier] animated:YES];
        }
    }
}

- (PSSpecifier *)_notchSpecifier
{
    PSSpecifier *notchSpecifier = [PSSpecifier preferenceSpecifierNamed:LOCALIZE(HIDE_NOTCHES) 
                                                                       target:self
                                                                          set:@selector(setPreferenceValue:specifier:)
                                                                          get:@selector(readPreferenceValue:)
                                                                       detail:nil
                                                                         cell:PSSwitchCell
                                                                         edit:nil];
    
    [notchSpecifier setProperty:@"STKHideGrabbers" forKey:@"key"];
    [notchSpecifier setProperty:NotchesSpecifierID forKey:@"id"];
    [notchSpecifier setProperty:@"com.a3tweaks.apex.prefschanged" forKey:@"PostNotification"];
    [notchSpecifier setProperty:@"com.a3tweaks.Apex" forKey:@"defaults"];

    return notchSpecifier;
}

#ifdef DEBUG
- (void)__deletePreferences
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"All preferences will be deleted, but layouts will be preserved." delegate:(id<UIActionSheetDelegate>)self cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Confirm" otherButtonTitles:nil];
    [actionSheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)idx
{
    if (idx == actionSheet.destructiveButtonIndex) {
        [[NSFileManager defaultManager] removeItemAtPath:kPrefPath error:nil];
        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
        EXECUTE_BLOCK_AFTER_DELAY(0.5, ^{
            system("killall -9 backboardd");
        });
    }
}
#endif

- (id)navigationTitle
{
    return @"Apex";
}

- (NSString *)title
{    
    return @"Apex";
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, -6.0f, 320.0f, 84.0f)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.layer.contentsGravity = kCAGravityCenter;
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textColor = TEXT_COLOR;
    label.font = [UIFont systemFontOfSize:72.0f];
    label.shadowColor = [UIColor whiteColor];
    label.shadowOffset = CGSizeMake(0, 1);
    label.text = @"Apex";
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 320.0f, 54.0f)];
    [header addSubview:label];
    [label release];
    [self table].tableHeaderView = header;
    [header release];
    for (PSSpecifier *specifier in self.specifiers) {
        specifier.target = self;
    }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)showHeartDialog
{
    if ([TWTweetComposeViewController canSendTweet])
    {        
        TWTweetComposeViewController *controller = [[TWTweetComposeViewController alloc] init];
        controller.completionHandler = ^(TWTweetComposeViewControllerResult res) {
            [controller dismissModalViewControllerAnimated:YES];            
            [controller release];
        };
        [controller setInitialText:LOCALIZE(LOVE_GAMES)];
        
        UIViewController *presentController = self;
        [presentController presentViewController:controller animated:YES completion:NULL];
    } else {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:LOCALIZE(CANNOT_SEND_TWEET) message:LOCALIZE(CANNOT_SEND_TWEET_DETAILS) delegate:nil cancelButtonTitle:LOCALIZE(OK) otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}
#pragma clang diagnostic pop


static inline void LoadDeviceKey(NSMutableDictionary *dict, NSString *key)
{
    id result = [[UIDevice currentDevice] deviceInfoForKey:key];
    if (result) {
        [dict setObject:result forKey:key];
    }
}

- (void)showMailDialog
{
    if ([MFMailComposeViewController canSendMail])
    {
        MFMailComposeViewController *mailViewController = [[MFMailComposeViewController alloc] init];
        mailViewController.mailComposeDelegate = self;
        [mailViewController setSubject:[LOCALIZE(APEX_SUPPORT) stringByAppendingString:@" v"kPackageVersion]];
        [mailViewController setToRecipients:[NSArray arrayWithObject:@"apexsupport@a3tweaks.com"]];
        NSString *filePath = kPrefPath;

        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:filePath] ?: [NSMutableDictionary dictionary];
        LoadDeviceKey(dict, @"UniqueDeviceID");
        LoadDeviceKey(dict, @"ProductVersion");
        LoadDeviceKey(dict, @"ProductType");
        LoadDeviceKey(dict, @"DiskUsage");
        LoadDeviceKey(dict, @"DeviceColor");
        LoadDeviceKey(dict, @"CPUArchitecture");

#ifdef kPackageVersion
        [dict setObject:@kPackageVersion forKey:@"Version"];
#endif
        NSString *packageDetails = [NSString stringWithContentsOfFile:@"/var/lib/dpkg/status" encoding:NSUTF8StringEncoding error:NULL];

        NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        if (data) {
            [mailViewController addAttachmentData:data mimeType:@"application/x-plist" fileName:[filePath lastPathComponent]];
        }

        [mailViewController addAttachmentData:[packageDetails dataUsingEncoding:NSUTF8StringEncoding] mimeType:@"text/plain" fileName:[@"user_package_list_" stringByAppendingString:dict[@"UniqueDeviceID"]]];

        [self presentViewController:mailViewController animated:YES completion:NULL];
        [mailViewController release];
    }
    else{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:LOCALIZE(CANNOT_SEND_MAIL) message:LOCALIZE(CANNOT_SEND_MAIL_DETAILS) delegate:nil cancelButtonTitle:LOCALIZE(OK) otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{              
    [self dismissViewControllerAnimated:YES completion:NULL];
}

@end