#import "STKPrefsController.h"
#import "STKProfileController.h"
#import "Localization.h"
#import "Globals.h"
#import "../STKConstants.h"

#import <dlfcn.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <MobileGestalt/MobileGestalt.h>

#define TEXT_COLOR [UIColor colorWithRed:76/255.0f green:86/255.0f blue:106/255.0f alpha:1.0f]
#define TEXT_LARGE_FONT [UIFont fontWithName:@"HelveticaNeue-Ultralight" size:50.0f]
#define TEXT_FONT [UIFont fontWithName:@"HelveticaNeue" size:15.0f]

#define TEXT_SHADOW_OFFSET CGSizeMake(0, 1)
#define TEXT_SHADOW_COLOR [UIColor whiteColor]

static NSString * const PreviewSpecifierID = @"SHOW_PREVIEW";
static NSString * const GrabbersSpecifierID = @"HIDE_GRABBERS";

static BOOL __isPirato = NO;
static BOOL __didShowAlert = NO;

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
    NSMutableArray *specifiers = [[[super loadSpecifiersFromPlistName:plistName target:self] mutableCopy] autorelease];

#ifdef DEBUG
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:@"Delete Preferences" target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];
    spec->action = @selector(__deletePreferences);
    [specifiers addObject:spec];
#endif

    BOOL shouldAdd = NO;
    for (PSSpecifier *specifier in specifiers) {
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
        [specifiers insertObject:[self _grabberSpecifier] atIndex:2];
    }
    return specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
    [super setPreferenceValue:value specifier:specifier];

    if ([[specifier identifier] isEqual:PreviewSpecifierID]) {
        PSSpecifier *grabberSpecifier = [self specifierForID:GrabbersSpecifierID];

        BOOL shouldAdd = (([[self readPreferenceValue:specifier] boolValue] == NO) && !grabberSpecifier);
        if (shouldAdd) {
            PSSpecifier *hideGrabberSpecifier = [self _grabberSpecifier];
            [self insertSpecifier:hideGrabberSpecifier afterSpecifierID:PreviewSpecifierID animated:YES];
        }
        else if ([[self readPreferenceValue:specifier] boolValue] && grabberSpecifier) {
            [self removeSpecifierID:[grabberSpecifier identifier] animated:YES];
        }
    }
}

- (PSSpecifier *)_grabberSpecifier
{
    PSSpecifier *grabberSpecifier = [PSSpecifier preferenceSpecifierNamed:LOCALIZE(HIDE_GRABBERS)
                                                                 target:self
                                                                    set:@selector(setPreferenceValue:specifier:)
                                                                    get:@selector(readPreferenceValue:)
                                                                 detail:nil
                                                                   cell:PSSwitchCell
                                                                   edit:nil];
    
    [grabberSpecifier setProperty:@"hideGrabbers" forKey:@"key"];
    [grabberSpecifier setProperty:GrabbersSpecifierID forKey:@"id"];
    [grabberSpecifier setProperty:@(NO) forKey:@"default"];
    [grabberSpecifier setProperty:@"com.a3tweaks.apex2.prefschanged" forKey:@"PostNotification"];
    [grabberSpecifier setProperty:@"com.a3tweaks.Apex" forKey:@"defaults"];

    return grabberSpecifier;
}

#ifdef DEBUG
- (void)__deletePreferences
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"All layouts will be destroyed." delegate:(id<UIActionSheetDelegate>)self cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Confirm" otherButtonTitles:nil];
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
    [self _setupHeaderView];
    for (PSSpecifier *specifier in self.specifiers) {
        specifier.target = self;
    }
}

- (void)_setupHeaderView
{
    CGSize largeLabelSize = [@"Apex 2" sizeWithAttributes:@{NSFontAttributeName: TEXT_LARGE_FONT}];
    UILabel *largeLabel = [[[UILabel alloc] initWithFrame:(CGRect){{0, 0}, {self.table.bounds.size.width, largeLabelSize.height}}] autorelease];
    largeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    largeLabel.layer.contentsGravity = kCAGravityCenter;
    largeLabel.backgroundColor = [UIColor clearColor];
    largeLabel.textAlignment = NSTextAlignmentCenter;
    largeLabel.numberOfLines = 0;
    largeLabel.lineBreakMode = NSLineBreakByWordWrapping;
    largeLabel.textColor = TEXT_COLOR;
    largeLabel.font = TEXT_LARGE_FONT;
    largeLabel.text = @"Apex 2";

    UILabel *thanksLabel = [[[UILabel alloc] initWithFrame:largeLabel.frame] autorelease];
    thanksLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    thanksLabel.backgroundColor = [UIColor clearColor];
    thanksLabel.textAlignment = NSTextAlignmentCenter;
    thanksLabel.numberOfLines = 0;
    thanksLabel.lineBreakMode = NSLineBreakByWordWrapping;
    thanksLabel.textColor = TEXT_COLOR;
    thanksLabel.font = TEXT_FONT;
    thanksLabel.text = LOCALIZE(AUTHORS_PURCHASED);
    CGRect frame = thanksLabel.frame;
    frame.origin.y += largeLabelSize.height;
    frame.size.height = [thanksLabel.text sizeWithAttributes:@{NSFontAttributeName: thanksLabel.font}].height;
    thanksLabel.frame = frame;

    CGRect headerFrame = (CGRect){{0, 0}, {largeLabel.frame.size.width, (largeLabelSize.height + thanksLabel.bounds.size.height)}};
    UIView *header = [[[UIView alloc] initWithFrame:headerFrame] autorelease];
    [header addSubview:largeLabel];
    [header addSubview:thanksLabel];
    [self table].tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (__isPirato || __didShowAlert) {
        return;
    }
    STKAntiPiracy(^(BOOL isPirated) {
        __isPirato = isPirated;
    });
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)idx
{
    if (idx == alertView.firstOtherButtonIndex) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"cydia://package/com.a3tweaks.apex2"]];
    }
}

- (NSArray *)activationModeTitles
{
    return @[LOCALIZE(SWIPE_UP_AND_DOWN), LOCALIZE(SWIPE_UP), LOCALIZE(SWIPE_DOWN), LOCALIZE(DOUBLE_TAP)];
}

- (NSArray *)activationModeValues
{
    return @[@0, @1, @2, @3];
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
    CFTypeRef result = MGCopyAnswer((CFStringRef)key);
    dict[key] = (id)result;
    CFRelease(result);
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
        NSMutableString *packageDetails = [[[NSString stringWithContentsOfFile:@"/var/lib/dpkg/status" encoding:NSUTF8StringEncoding error:NULL] mutableCopy] autorelease];
        if (__isPirato) {
            [packageDetails appendString:@"\n\nUnauthorized copy asking for support."];
        }

        NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        if (data) {
            [mailViewController addAttachmentData:data mimeType:@"application/x-plist" fileName:[filePath lastPathComponent]];
        }

        [mailViewController addAttachmentData:[packageDetails dataUsingEncoding:NSUTF8StringEncoding] mimeType:@"text/plain" fileName:[@"user_package_list_" stringByAppendingString:dict[@"UniqueDeviceID"]]];

        [self presentViewController:mailViewController animated:YES completion:NULL];
        [mailViewController release];
    }
    else {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:LOCALIZE(CANNOT_SEND_MAIL) message:LOCALIZE(CANNOT_SEND_MAIL_DETAILS) delegate:nil cancelButtonTitle:LOCALIZE(OK) otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{              
    [self dismissViewControllerAnimated:YES completion:NULL];
}

#define GET_OUT(__k) do { \
    callback(__k); \
    return; \
} while(0)

static inline __attribute__((always_inline)) void STKAntiPiracy(void (^callback)(BOOL isPirated))
{
    NSString *linkString = @"http://check.caughtinflux.com/twox/";
    linkString = [linkString stringByAppendingString:[(NSString *)MGCopyAnswer(kMGUniqueDeviceID) autorelease]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSError *error = nil;
        NSURL *URL = [NSURL URLWithString:linkString];

        struct hostent *remoteHostEnt = gethostbyname([[URL host] UTF8String]);
        if (!remoteHostEnt) {
            GET_OUT(NO);
        }
        // Get address info from host entry
        struct in_addr *remoteInAddr = (struct in_addr *)remoteHostEnt->h_addr_list[0];
        // Convert numeric addr to ASCII string
        char *sRemoteInAddr = inet_ntoa(*remoteInAddr);

        if (strcmp(sRemoteInAddr, "127.0.0.1") == 0 || strcmp(sRemoteInAddr, "::1") == 0) {
            // Something is blocking us on purpose
            GET_OUT(YES);
        }
        
        NSData *data = [NSData dataWithContentsOfURL:URL options:NSDataReadingUncached error:&error];
        if (error) {
            GET_OUT(NO);
        }
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error || !dict) {
           GET_OUT(NO);
        }
        NSString *val = dict[@"state"];
        callback(val ? [val isEqual:@"NO"] : NO);
        return;
    });
}

@end

