#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <GraphicsServices/GraphicsServices.h>
#import <dlfcn.h>
#import <substrate.h>

#define kSTKSpringBoardPortName           CFSTR("com.a3tweaks.apex.springboardport")
#define kSTKSearchdPortName               CFSTR("com.a3tweaks.apex.searchdport")
#define kSTKIdentifiersRequestMessageName @"com.a3tweaks.apex.searchd.wantshiddenidents"
#define kSTKIdentifiersRequestMessageID   (SInt32)1337
#define kSTKIdentifiersUpdateMessageID    (SInt32)1234

static CFMessagePortRef _localPort;
static CFMessagePortRef _remotePort;
static NSArray *_stackedIconIdentifiers;

static void STKUpdateIdentifiers(void)
{
    if (!_remotePort) {
        NSLog(@"Cannot establish a connection to SpringBoard!");
        return;
    }

    CFDataRef returnData = NULL;
    NSLog(@"Retrieving stacked icon identifiers from SpringBoard");
    SInt32 err = CFMessagePortSendRequest(_remotePort,
                                          kSTKIdentifiersRequestMessageID,
                                          (CFDataRef)[kSTKIdentifiersRequestMessageName dataUsingEncoding:NSUTF8StringEncoding],
                                          1,
                                          1,
                                          kCFRunLoopDefaultMode,
                                          &returnData);

    if (err != kCFMessagePortSuccess) {
        NSLog(@"An error occurred whilst requesting updated identifiers from SpringBoard: %i", (int)err);
    }
    
    if (!returnData) {
        return;
    }

    [_stackedIconIdentifiers release];
    _stackedIconIdentifiers = [[NSKeyedUnarchiver unarchiveObjectWithData:(NSData *)returnData] copy];
}

CFPropertyListRef (*o_GSSystemCopyCapability)(CFStringRef cap);
CFPropertyListRef n_GSSystemCopyCapability(CFStringRef cap)
{
    CFPropertyListRef ret = o_GSSystemCopyCapability(cap);
    
    if (CFStringCompare(cap, kGSDisplayIdentifiersCapability, 0) == kCFCompareEqualTo) {
        NSMutableArray *identifiers = [[NSMutableArray arrayWithArray:(NSArray *)ret] retain];
        if (_stackedIconIdentifiers) {
            [identifiers addObjectsFromArray:_stackedIconIdentifiers];
        }
        
        return (CFPropertyListRef)identifiers;
    }

    return ret;
}

CFDataRef STKLocalPortCallBack(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info)
{
    if (msgid != kSTKIdentifiersUpdateMessageID) {
        return NULL;
    }
    if (data) {
        [_stackedIconIdentifiers release];
        _stackedIconIdentifiers = [[NSKeyedUnarchiver unarchiveObjectWithData:(NSData *)data] copy];
    }
    return NULL;
}

%ctor
{
    @autoreleasepool {
        _localPort = CFMessagePortCreateLocal(kCFAllocatorDefault, 
                                              kSTKSearchdPortName,
                                              (CFMessagePortCallBack)STKLocalPortCallBack,
                                              NULL,
                                              NULL);

        // Set up the local port to receive messages, so the tweak can update us about any changes to the stacked icons
        CFRunLoopSourceRef runLoopSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, _localPort, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);

        _remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, kSTKSpringBoardPortName);

        STKUpdateIdentifiers();

        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/GraphicsServices.framework"] load];
        
        void *func = (void *)(CFPropertyListRef(*)(CFStringRef))dlsym(RTLD_DEFAULT, "GSSystemCopyCapability");
        MSHookFunction(func, (void *)n_GSSystemCopyCapability, (void **)&o_GSSystemCopyCapability);

        [[NSBundle bundleWithPath:@"/System/Library/SearchBundles/Application.searchBundle"] load];
    }
}

__attribute__((destructor)) void _tearDown (void)
{
    CFMessagePortInvalidate(_localPort);
    CFRelease(_localPort);
    CFRelease(_remotePort);
}
