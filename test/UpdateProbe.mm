#import "UpdateProbe.h"
#import <Sparkle/Sparkle.h>

@interface SLUpdateProbe : NSObject <SPUUserDriver, SPUUpdaterDelegate>
@property SPUUpdater *updater;
@property NSString *result;
@property NSString *mode;
- (void)record:(NSString *)stage error:(NSString *)error;
@end
@implementation SLUpdateProbe
- (void)record:(NSString *)stage error:(NSString *)error {
    NSDictionary *value=@{@"stage":stage,@"error":error ?: @"",@"version":NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]};
    [[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil] writeToFile:_result atomically:YES];
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:YES automaticUpdateDownloading:@YES sendSystemProfile:NO]);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    [self record:@"failed" error:error.description]; acknowledgement(); [NSApp terminate:nil];
}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    [self record:@"failed" error:error.description]; acknowledgement(); [NSApp terminate:nil];
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {
    // The fixture exercises install-on-quit and launches again from its harness.
    reply(SPUUserUpdateChoiceDismiss);
    [self record:@"ready" error:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [NSApp terminate:nil]; });
}
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); }
- (void)dismissUpdateInstallation {}
- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)updater { return NO; }
- (BOOL)updater:(SPUUpdater *)updater willInstallUpdateOnQuit:(SUAppcastItem *)item immediateInstallationBlock:(void (^)(void))handler {
    [self record:@"ready" error:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ [NSApp terminate:nil]; });
    return NO;
}
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error {
    [self record:@"failed" error:error.description]; [NSApp terminate:nil];
}
@end

BOOL SLStartUpdateProbe(NSString *profile) {
    NSDictionary *env=NSProcessInfo.processInfo.environment;
    NSString *mode=env[@"SEARCHLIGHT_UPDATE_PROBE"];
    NSString *parent=profile.stringByDeletingLastPathComponent;
    NSBundle *bundle=NSBundle.mainBundle;
    if (![mode isEqual:@"install"] && ![mode isEqual:@"verify"]) return NO;
    if (![parent.lastPathComponent hasPrefix:@"searchlight-smoke-"] ||
        ![bundle.bundleIdentifier hasPrefix:@"nl.martnr.mica.update-test."] ||
        ![bundle.bundlePath hasPrefix:[parent stringByAppendingString:@"/"]]) return NO;
    static SLUpdateProbe *probe;
    probe=[SLUpdateProbe new]; probe.mode=mode;
    probe.result=[parent stringByAppendingPathComponent:@"update-result.json"];
    if ([mode isEqual:@"verify"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [probe record:@"relaunched" error:nil]; [NSApp terminate:nil]; });
        return YES;
    }
    probe.updater=[[SPUUpdater alloc] initWithHostBundle:bundle applicationBundle:bundle userDriver:probe delegate:probe];
    NSError *error=nil;
    if (![probe.updater startUpdater:&error]) { [probe record:@"failed" error:error.description]; [NSApp terminate:nil]; return YES; }
    [probe.updater checkForUpdatesInBackground];
    return YES;
}
