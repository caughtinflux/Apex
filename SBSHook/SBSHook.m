#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <SpringBoardServices/SpringBoardServices.h>
#import <substrate.h>

#define kPrefPath [NSString stringWithFormat:@"%@/Library/Preferences/com.a3tweaks.Apex.plist", NSHomeDirectory()]

static NSArray *_subappIdentifiers = nil;

void STKUpdateIdentifiers(void)
{
    [_subappIdentifiers release];
    _subappIdentifiers = [NSMutableArray new];
    NSDictionary *iconState = [NSDictionary dictionaryWithContentsOfFile:kPrefPath][@"state"];
    for (NSString *groupIdent in [iconState allKeys]) {
        NSMutableArray *currentGroupSubappIdents = [NSMutableArray array];
        for (NSArray *icons in [iconState[groupIdent][@"layout"] allValues]) {
            if (icons.count > 0) {
                [currentGroupSubappIdents addObjectsFromArray:icons];
            }
        }
        [(NSMutableArray *)_subappIdentifiers addObjectsFromArray:currentGroupSubappIdents];
    }
}

static void STKLayoutsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    STKUpdateIdentifiers();
}

CFSetRef (*original_SBSCopyDisplayIdentifiers)(void);
CFSetRef new_SBSCopyDisplayIdentifiers(void)
{
    CFSetRef originalSet = original_SBSCopyDisplayIdentifiers();
    CFMutableSetRef modifiedSet = CFSetCreateMutableCopy(NULL, 0, originalSet);
    CFRelease(originalSet);
    for (NSString *identifier in _subappIdentifiers) {
        CFSetAddValue(modifiedSet, (CFStringRef)identifier);
    }
    return modifiedSet;
}

static __attribute__((constructor)) void _construct(void)
{
    @autoreleasepool {
        STKUpdateIdentifiers();
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/SpringBoardServices.framework"] load];
        MSHookFunction(SBSCopyDisplayIdentifiers, (void *)new_SBSCopyDisplayIdentifiers, (void **)&original_SBSCopyDisplayIdentifiers);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        STKLayoutsChanged,
                                        CFSTR("com.a3tweaks.apex.iconstatechanged"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
