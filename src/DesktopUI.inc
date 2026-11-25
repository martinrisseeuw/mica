// Native desktop integration. This action never runs automatically on startup.
- (void)makeDefaultBrowser:(id)sender {
    if (_settingDefaultBrowser || _quitting || SLIsDefaultBrowser()) return;
    _settingDefaultBrowser=YES;
    __weak SLController *owner=self;
    SLRequestDefaultBrowser(^(NSError *error) {
        SLController *controller=owner; if (!controller) return;
        controller.settingDefaultBrowser=NO;
        if (controller.quitting) return;
        if (error) {
            if (error.code==NSUserCancelledError || error.code==-128) return;
            NSAlert *alert=[NSAlert new]; alert.messageText=@"Couldn’t set the default browser";
            alert.informativeText=@"You can also choose Mica in System Settings → Desktop & Dock → Default web browser.";
            [alert addButtonWithTitle:@"OK"]; [alert beginSheetModalForWindow:controller.window completionHandler:nil];
        } else if (SLIsDefaultBrowser()) controller.status.stringValue=@"Mica is your default browser.";
    });
}
- (void)openExternalURLArguments:(NSArray<NSString *> *)arguments {
    if (_quitting) return;
    NSMutableArray *urls=[NSMutableArray array];
    for (NSString *argument in arguments) { NSString *url=SLExternalWebURL(argument); if (url) [urls addObject:url]; }
    if (!urls.count) return;
    if (!_window) { [_pendingExternalURLs addObjectsFromArray:urls]; return; }
    for (NSString *url in urls) {
        // Reuse an untouched empty tab; otherwise open a separate tab.
        if (!_activeTab.url.length && !_homeAddress.stringValue.length) [self navigate:url];
        else [self addTabURL:url];
    }
    [NSApp activateIgnoringOtherApps:YES]; [_window makeKeyAndOrderFront:nil];
    if (_activeTab->chrome) _activeTab->chrome->Focus();
}
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray *arguments=[NSMutableArray array];
    for (NSURL *url in urls) if (url.absoluteString) [arguments addObject:url.absoluteString];
    [self openExternalURLArguments:arguments];
}
- (void)handleOpenURLEvent:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply {
    NSString *url=[event paramDescriptorForKeyword:keyDirectObject].stringValue;
    if (url) [self openExternalURLArguments:@[url]];
}
