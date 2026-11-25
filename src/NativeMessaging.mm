#import "NativeMessaging.h"
#import <Security/Security.h>

BOOL SLInstallOnePasswordConnector(NSString *profile, NSString *applicationPath) {
    if (!profile.isAbsolutePath || !applicationPath.isAbsolutePath) return NO;
    NSString *helper=[applicationPath stringByAppendingPathComponent:@"Contents/Library/LoginItems/1Password Browser Helper.app/Contents/MacOS/1Password-BrowserSupport"];
    SecStaticCodeRef code=nullptr; SecRequirementRef requirement=nullptr;
    OSStatus status=SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:helper],kSecCSDefaultFlags,&code);
    if (status!=errSecSuccess) return NO;
    status=SecRequirementCreateWithString(CFSTR("anchor apple generic and identifier \"com.1password.browser-support\" and certificate leaf[subject.OU] = \"2BUA8C4S2C\""),kSecCSDefaultFlags,&requirement);
    if (status==errSecSuccess) status=SecStaticCodeCheckValidity(code,kSecCSCheckAllArchitectures,requirement);
    if (requirement) CFRelease(requirement);
    CFRelease(code);
    if (status!=errSecSuccess) return NO;
    NSDictionary *manifest=@{@"name":@"com.1password.1password",@"description":@"1Password BrowserSupport",@"type":@"stdio",@"path":helper,
        @"allowed_origins":@[@"chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"]};
    NSString *directory=[profile stringByAppendingPathComponent:@"NativeMessagingHosts"];
    NSFileManager *files=NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    NSString *path=[directory stringByAppendingPathComponent:@"com.1password.1password.json"];
    NSData *data=[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:nil]) return NO;
    return [files setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
