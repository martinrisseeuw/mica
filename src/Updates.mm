#import "Updates.h"
#import <Sparkle/Sparkle.h>

@interface SLUpdates ()
@property SPUStandardUpdaterController *controller;
@property BOOL enabled;
@property (readwrite) BOOL started;
@end

@implementation SLUpdates
- (instancetype)initWithEnabled:(BOOL)enabled {
    if ((self=[super init])) {
        _enabled=enabled;
        if (enabled) _controller=[[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO updaterDelegate:nil userDriverDelegate:nil];
    }
    return self;
}
- (void)start {
    if (!_enabled || _started) return;
    NSError *error=nil;
    _started=[_controller.updater startUpdater:&error];
    if (!_started) { NSLog(@"Mica updater could not start: %@",error.localizedDescription); return; }
    // Sparkle owns the schedule and preferences; check once on launch too.
    if (_controller.updater.automaticallyChecksForUpdates) [_controller.updater checkForUpdatesInBackground];
}
- (void)checkForUpdates:(id)sender {
    if (_started) [_controller checkForUpdates:sender];
}
- (void)toggleAutomaticUpdates:(id)sender {
    if (!_started) return;
    SPUUpdater *updater=_controller.updater;
    BOOL automatic=!(updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates);
    updater.automaticallyChecksForUpdates=automatic;
    updater.automaticallyDownloadsUpdates=automatic;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action==@selector(checkForUpdates:)) return _started && _controller.updater.canCheckForUpdates;
    if (item.action==@selector(toggleAutomaticUpdates:)) {
        item.state=(_controller.updater.automaticallyChecksForUpdates && _controller.updater.automaticallyDownloadsUpdates)?NSControlStateValueOn:NSControlStateValueOff;
        return _started;
    }
    return NO;
}
@end
