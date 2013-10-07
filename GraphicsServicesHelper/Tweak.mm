#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <GraphicsServices/GraphicsServices.h>
#import <dlfcn.h>
#import <substrate.h>

#define kSTKTweakName @"Apex"
#define DLog(fmt, ...) NSLog((@"[%@] %s [Line %d] " fmt), kSTKTweakName, __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#define CLog(fmt, ...) NSLog((@"[%@] " fmt), kSTKTweakName, ##__VA_ARGS__)

#define kSTKSpringBoardPortName           CFSTR("com.a3tweaks.apex.springboardport")
#define kSTKIdentifiersRequestMessageName @"com.a3tweaks.apex.GraphicsServices.wantshiddenidents"
#define kSTKIdentifiersRequestMessageID   (SInt32)1337

static CFMessagePortRef _remotePort = NULL;
static NSArray *_stackedIconIdentifiers = nil;

BOOL STKUpdateIdentifiers(void)
{
    if (!_remotePort) {
        NSLog(@"[Apex] Cannot establish a connection to SpringBoard!");
        return NO;
    }

    CFDataRef returnData = NULL;
    SInt32 err = CFMessagePortSendRequest(_remotePort,
                                          kSTKIdentifiersRequestMessageID,
                                          (CFDataRef)[kSTKIdentifiersRequestMessageName dataUsingEncoding:NSUTF8StringEncoding],
                                          0.5,
                                          0.5,
                                          kCFRunLoopDefaultMode,
                                          &returnData);

    if (err != kCFMessagePortSuccess) {
        NSLog(@"[Apex] An error occurred whilst requesting updated identifiers from SpringBoard: %i", (int)err);
        return NO;
    }
    
    if (!returnData) {
        return NO;
    }

    [_stackedIconIdentifiers release];
    _stackedIconIdentifiers = [[NSKeyedUnarchiver unarchiveObjectWithData:(NSData *)returnData] copy];
    if (!_stackedIconIdentifiers) {
        return NO;
    }
    return YES;
}

CFPropertyListRef (*original_GSSystemCopyCapability)(CFStringRef cap);
CFPropertyListRef new_GSSystemCopyCapability(CFStringRef cap)
{
    CFPropertyListRef ret = original_GSSystemCopyCapability(cap);
    
    if (cap == NULL) {
        NSMutableDictionary *capabilites = [(NSDictionary *)ret mutableCopy];
        NSMutableArray *displayIDs = [[(NSArray *)[capabilites objectForKey:(NSString *)kGSDisplayIdentifiersCapability] mutableCopy] autorelease];
        if (displayIDs && _stackedIconIdentifiers) {
            [displayIDs addObjectsFromArray:_stackedIconIdentifiers];
        }

        capabilites[(NSString *)kGSDisplayIdentifiersCapability] = displayIDs;
        return capabilites;
    }

    if (CFStringCompare(cap, kGSDisplayIdentifiersCapability, 0) == kCFCompareEqualTo) {
        NSMutableArray *identifiers = [[NSMutableArray arrayWithArray:(NSArray *)ret] retain];
        if (_stackedIconIdentifiers) {
            [identifiers addObjectsFromArray:_stackedIconIdentifiers];
        }
        
        return (CFPropertyListRef)identifiers;
    }

    return ret;
}

static __attribute__((constructor)) void _construct(void)
{
    @autoreleasepool {
        _remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, kSTKSpringBoardPortName);
        BOOL success = STKUpdateIdentifiers();
        if (success == NO) {
            return;
        }

        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/GraphicsServices.framework"] load];
        void *func = (void *)dlsym(RTLD_DEFAULT, "GSSystemCopyCapability");
        MSHookFunction(func, (void *)new_GSSystemCopyCapability, (void **)&original_GSSystemCopyCapability);     
    }
}

static __attribute__((destructor)) void _tearDown(void)
{
    if (_remotePort) {
        CFRelease(_remotePort);
    }
}
