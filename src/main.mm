#import <Cocoa/Cocoa.h>
#import "Browser.h"
#import "Model.h"
#import "NativeMessaging.h"
#import "Profile.h"
#include "ChromeExtensions.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include <limits.h>
#include <stdlib.h>

static __weak SLController *activeBrowserController;

class BrowserApp final : public CefApp, public CefBrowserProcessHandler {
public:
    explicit BrowserApp(bool testMode) : testMode_(testMode) {}
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
    void OnBeforeCommandLineProcessing(const CefString& type, CefRefPtr<CefCommandLine> command) override {
        // Only the disposable localhost smoke-test profile can opt into this.
        // Ordinary browsing always uses Mica's own real Keychain item.
        if (type.empty() && testMode_) {
            command->AppendSwitch("use-mock-keychain");
            // A fixture under the already-validated disposable profile only.
            if ([NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_EXTENSION_PROBE"] isEqual:@"1"]) {
                NSString *fixture=[NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_PROFILE"] stringByAppendingPathComponent:@"extension-fixture"];
                NSString *popup=[NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_PROFILE"] stringByAppendingPathComponent:@"popup-fixture"];
                command->AppendSwitchWithValue("load-extension",[NSString stringWithFormat:@"%@,%@",fixture,popup].UTF8String);
            }
            if ([NSProcessInfo.processInfo.environment[@"MICA_IMPORT_PROBE"] isEqual:@"1"]) {
                NSString *fixture=[NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_PROFILE"] stringByAppendingPathComponent:@"import-fixture"];
                command->AppendSwitchWithValue("load-extension",fixture.UTF8String);
            }
            command->AppendSwitchWithValue("host-resolver-rules","MAP doubleclick.net 127.0.0.1");
        }
    }
    CefRefPtr<CefClient> GetDefaultClient() override { return SLDefaultChromeClient(); }
    bool OnAlreadyRunningAppRelaunch(CefRefPtr<CefCommandLine> commandLine, const CefString&) override {
        CefCommandLine::ArgumentList arguments; commandLine->GetArguments(arguments);
        NSMutableArray *urls=[NSMutableArray array];
        for (const auto &argument : arguments) [urls addObject:[NSString stringWithUTF8String:argument.ToString().c_str()] ?: @""];
        [activeBrowserController openExternalURLArguments:urls];
        [NSApp activateIgnoringOtherApps:YES];
        for (NSWindow *window in NSApp.windows) if ([window.title containsString:@"Mica"]) [window makeKeyAndOrderFront:nil];
        return true;
    }
private:
    bool testMode_;
    IMPLEMENT_REFCOUNTING(BrowserApp);
};

@interface SLApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@property(nonatomic, strong) SLController *browserController;
@end
@implementation SLApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event {
    // Quit belongs to the browser shell, including while a Chrome child
    // surface has focus. Avoid Chrome's separate application-quit route.
    NSEventModifierFlags modifiers=event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagOption|NSEventModifierFlagControl|NSEventModifierFlagShift);
    if (event.type==NSEventTypeKeyDown && modifiers==NSEventModifierFlagCommand && [event.charactersIgnoringModifiers.lowercaseString isEqual:@"q"] && self.browserController) {
        [self terminate:nil]; return;
    }
    CefScopedSendingEvent sendingEvent;
    [super sendEvent:event];
}
// Chromium temporarily installs its AppController as NSApp.delegate while
// routing menu/key commands. It does not implement Mica's requestQuit method.
// Keep an explicit target so Command-Q and Dock Quit use our CEF close sequence.
- (void)terminate:(id)sender { [self.browserController requestQuit]; }
@end

int main(int argc, char *argv[]) {
    CefScopedLibraryLoader loader;
    if (!loader.LoadInMain()) return 1;
    @autoreleasepool {
        [SLApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSDictionary *env=NSProcessInfo.processInfo.environment;
        NSString *support=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        NSDictionary *configuration=SLProfileConfiguration(support,env);
        if ([configuration[@"needsChoice"] boolValue]) {
            [NSApp activateIgnoringOtherApps:YES];
            NSAlert *choice=[NSAlert new];
            choice.messageText=@"Welcome to Mica";
            choice.informativeText=@"Your earlier Searchlight data is still on this Mac. Start Fresh creates a new profile and leaves that data untouched. Keep My Data reuses your tabs and website sign-ins; macOS may ask you to allow access to their encryption key.";
            [choice addButtonWithTitle:@"Start Fresh"];
            [choice addButtonWithTitle:@"Keep My Data"];
            [choice addButtonWithTitle:@"Quit"];
            NSModalResponse response=[choice runModal];
            if (response!=NSAlertFirstButtonReturn && response!=NSAlertSecondButtonReturn) return 0;
            NSError *error=nil;
            if (!SLSaveProfileChoice(support,response==NSAlertSecondButtonReturn,&error)) {
                [NSApp presentError:error]; return 1;
            }
            configuration=SLProfileConfiguration(support,env);
        }
        NSString *profile=configuration[@"path"];
        BOOL legacyIdentity=[configuration[@"legacy"] boolValue];
        if (!profile.isAbsolutePath) { fprintf(stderr,"MICA_PROFILE must be an absolute path.\n"); return 1; }
        [[NSFileManager defaultManager] createDirectoryAtPath:profile withIntermediateDirectories:YES attributes:nil error:nil];
        char resolved[PATH_MAX];
        if (realpath(profile.fileSystemRepresentation, resolved)) profile = [NSString stringWithUTF8String:resolved];
        [[NSFileManager defaultManager] createDirectoryAtPath:[profile stringByAppendingPathComponent:@"Engine"] withIntermediateDirectories:YES attributes:nil error:nil];
        CefSettings settings;
        settings.no_sandbox = false;
        settings.command_line_args_disabled = true;
        CefString(&settings.keychain_service_name) = legacyIdentity ? "Searchlight Safe Storage" : "Mica Safe Storage";
        CefString(&settings.keychain_account_name) = legacyIdentity ? "Searchlight" : "Mica";
        CefString(&settings.root_cache_path) = profile.UTF8String;
        CefString(&settings.cache_path) = [profile stringByAppendingPathComponent:@"Engine"].UTF8String;
        CefString(&settings.log_file) = [profile stringByAppendingPathComponent:@"chromium.log"].UTF8String;
        settings.log_severity = LOGSEVERITY_WARNING;
        NSDictionary *environment = NSProcessInfo.processInfo.environment;
        NSURL *testURL = [NSURL URLWithString:environment[@"SEARCHLIGHT_SMOKE_URL"] ?: @""];
        BOOL testMode = [environment[@"SEARCHLIGHT_TEST_MODE"] isEqual:@"1"] &&
            [profile.stringByDeletingLastPathComponent.lastPathComponent hasPrefix:@"searchlight-smoke-"] &&
            [testURL.host isEqual:@"127.0.0.1"] &&
            [environment[@"SEARCHLIGHT_SMOKE_RESULT"] length] > 0;
        if (!testMode) {
            NSURL *onePassword=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.1password.1password"];
            if (onePassword) SLInstallOnePasswordConnector(profile,onePassword.path);
        }
        CefMainArgs args(argc, argv);
        CefRefPtr<BrowserApp> browserApp = new BrowserApp(testMode);
        if (!CefInitialize(args, settings, browserApp, nullptr)) return CefGetExitCode();
        @autoreleasepool {
            SLController *controller = [[SLController alloc] initWithProfile:profile updatesEnabled:!testMode];
            activeBrowserController = controller;
            ((SLApplication *)NSApp).browserController = controller;
            NSApp.delegate = controller;
            [controller start];
            [controller openExternalURLArguments:NSProcessInfo.processInfo.arguments];
            CefRunMessageLoop();
            [NSAppleEventManager.sharedAppleEventManager removeEventHandlerForEventClass:kInternetEventClass andEventID:kAEGetURL];
            activeBrowserController = nil;
            NSApp.delegate = nil;
            ((SLApplication *)NSApp).browserController = nil;
            controller = nil;
        }
        if (testMode) fprintf(stderr,"smoke: starting CefShutdown\n");
        CefShutdown();
        if (testMode) fprintf(stderr,"smoke: finished CefShutdown\n");
        browserApp = nullptr;
    }
    return 0;
}
