- (NSURL *)applicationForExternalURL:(NSURL *)url {
    NSURL *application=[NSWorkspace.sharedWorkspace URLForApplicationToOpenURL:url];
    if (!application) return nil;
    // Avoid recursively handing a protocol back to this browser.
    if ([[NSBundle bundleWithURL:application].bundleIdentifier isEqual:NSBundle.mainBundle.bundleIdentifier]) return nil;
    return application;
}
- (void)openExternalAppURL:(NSURL *)url application:(NSURL *)application completion:(void (^)(NSError *))completion {
    [NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:application
        configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }];
}
- (void)requestExternalAppURL:(NSString *)url fromTab:(SLTab *)tab origin:(NSString *)origin {
    NSURL *destination=SLExternalAppURL(url);
    if (!destination || !SLExternalWebURL(origin) || _quitting || !tab || tab!=_activeTab || tab.closing || tab.rehosting ||
        !tab->browser || _externalAppPromptPending || _window.attachedSheet) return;
    _externalAppPromptPending=YES;
    NSUInteger generation=tab.navigationGeneration;
    // Leave CEF's navigation callback before presenting AppKit UI.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.quitting || self.activeTab!=tab || tab.closing || !tab->browser ||
            tab.navigationGeneration!=generation || self.window.attachedSheet) {
            self.externalAppPromptPending=NO; return;
        }
        NSURL *application=[self applicationForExternalURL:destination];
        NSString *name=application ? [NSFileManager.defaultManager displayNameAtPath:application.path].stringByDeletingPathExtension : nil;
        NSURLComponents *site=[NSURLComponents componentsWithString:origin];
        // Callback query strings/fragments may contain credentials; never display or log them.
        site.user=nil; site.password=nil; site.path=@""; site.query=nil; site.fragment=nil;
        NSAlert *alert=[NSAlert new];
        if (application) {
            alert.messageText=[NSString stringWithFormat:@"Open %@?",name];
            // CEF reports the target frame for top-level navigation, not always
            // the initiator (an embedded frame can target _top). Label this as
            // the current tab's site rather than attributing the request to it.
            alert.informativeText=[NSString stringWithFormat:@"A link in this tab will open %@.\n\nCurrent website: %@",name,site.string];
            [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Open App"];
        } else {
            alert.messageText=@"No app can open this link";
            alert.informativeText=[NSString stringWithFormat:@"Install an app that handles “%@” links, then try again.",destination.scheme];
            [alert addButtonWithTitle:@"OK"];
        }
        [self.window makeKeyAndOrderFront:nil];
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            self.externalAppPromptPending=NO;
            if (!application || response!=NSAlertSecondButtonReturn || self.quitting || self.activeTab!=tab ||
                tab.closing || !tab->browser || tab.navigationGeneration!=generation) return;
            [self openExternalAppURL:destination application:application completion:^(NSError *error) {
                if (!error || self.quitting) return;
                NSAlert *failure=[NSAlert new];
                failure.messageText=[NSString stringWithFormat:@"Couldn’t open %@",name];
                failure.informativeText=@"Open the app directly, then try the link again.";
                [failure addButtonWithTitle:@"OK"];
                [self.window makeKeyAndOrderFront:nil];
                // AppKit queues this sheet if the confirmation is still dismissing.
                [failure beginSheetModalForWindow:self.window completionHandler:nil];
            }];
        }];
    });
}
