- (NSButton *)importSmokeButton:(NSString *)title inView:(NSView *)view {
    if ([view isKindOfClass:NSButton.class] && [((NSButton *)view).title isEqual:title]) return (NSButton *)view;
    for (NSView *child in view.subviews) { NSButton *found=[self importSmokeButton:title inView:child]; if (found) return found; }
    return nil;
}
- (void)extensionImportSmokeTick {
    if (!_activeSpace.contextReady) return;
    NSString *identifier=NSProcessInfo.processInfo.environment[@"MICA_IMPORT_FIXTURE_ID"];
    NSDictionary *installed=[self installedExtensionsInSpace:_activeSpace][identifier];
    if (!installed) return;
    BOOL restore=[NSProcessInfo.processInfo.environment[@"MICA_IMPORT_RESTORE"] isEqual:@"1"];
    if (_smokeStep==0) {
        if (restore) {
            [self addTabURL:[NSString stringWithFormat:@"chrome-extension://%@/verify.html",identifier]];
            _smokeStep=4; return;
        }
        NSString *source=[_profile stringByAppendingPathComponent:@"chrome-source"];
        __weak SLController *owner=self;
        _importPanel=[[SLExtensionImportPanel alloc] initWithChromeRoot:source installed:[NSSet set] completion:^(NSArray<NSDictionary *> *selected) {
            SLController *controller=owner;
            if (selected.count!=1 || ![selected[0][@"count"] isEqual:@6]) { [controller smokeFinish:@"Native importer selection omitted supported settings"]; return; }
            NSDictionary *item=selected[0];
            [controller.extensionImports addObject:[@{@"id":item[@"id"],@"space":controller.activeSpace.uid,@"name":item[@"name"],@"settings":item[@"settings"],@"state":@"waiting"} mutableCopy]];
            if (![controller saveExtensionImports]) { [controller smokeFinish:@"Could not persist the import plan"]; return; }
            controller.importPanel=nil; [controller startExtensionImportTimer];
            controller.smokeStep=2;
        }];
        [_importPanel presentForWindow:_window]; _smokeStep=1; return;
    }
    if (_smokeStep==1) {
        NSArray *rows=[_importPanel valueForKey:@"choices"];
        if (rows.count!=1) return;
        NSButton *choice=rows[0]; if (!choice.enabled || ![choice.identifier isEqual:identifier]) { [self smokeFinish:@"Import selection did not find the Chrome fixture"]; return; }
        [choice performClick:nil];
        [self captureView:_importPanel.window.contentView filename:@"extension-import.png"];
        [[_importPanel valueForKey:@"importButton"] performClick:nil]; return;
    }
    if (_smokeStep==2) {
        NSDictionary *job=_extensionImports.firstObject;
        if ([job[@"state"] isEqual:@"failed"] || [job[@"state"] isEqual:@"done"] || _extensionImportTab) { [self smokeFinish:@"Settings must wait for explicit application after setup"]; return; }
        if (![job[@"state"] isEqual:@"ready"]) return;
        [self addTabURL:[NSString stringWithFormat:@"chrome-extension://%@/verify.html?setup",identifier]]; _smokeStep=20; return;
    }
    if (_smokeStep==20) {
        if ([_activeTab.title hasPrefix:@"Import failure:"]) { [self smokeFinish:_activeTab.title]; return; }
        if (![_activeTab.title isEqual:@"Setup verified"]) return;
        [_smokeChecks addObject:@"Delayed installation defaults finish before explicit settings application"];
        [self showExtensionImportProgress:nil];
        NSButton *apply=[self importSmokeButton:@"Apply settings" inView:_window.attachedSheet.contentView];
        if (!apply) { [self smokeFinish:@"Import Progress does not expose Apply settings"]; return; }
        [self captureView:_window.attachedSheet.contentView filename:@"extension-import-progress.png"];
        [apply performClick:nil]; _smokeStep=21; return;
    }
    if (_smokeStep==21) {
        NSDictionary *job=_extensionImports.firstObject;
        if ([job[@"state"] isEqual:@"failed"]) { [self smokeFinish:@"Runtime rejected extension settings import"]; return; }
        if (![job[@"state"] isEqual:@"done"]) return;
        if (!SLPreferenceCount(job[@"settings"][@"local"])) { [self smokeFinish:@"Completed import discarded its reapplication payload"]; return; }
        [_smokeChecks addObject:@"Native profile picker reads real Chrome-format settings and imports selected preferences"];
        _activeTab->browser->GetMainFrame()->ExecuteJavaScript("chrome.storage.local.set({theme:'light'}).then(()=>document.title='Reset simulated')","",0);
        _smokeStep=22; return;
    }
    if (_smokeStep==22) {
        if (![_activeTab.title isEqual:@"Reset simulated"]) return;
        [self showExtensionImportProgress:nil];
        NSButton *reapply=[self importSmokeButton:@"Reapply settings" inView:_window.attachedSheet.contentView];
        if (!reapply) { [self smokeFinish:@"Completed imports cannot be reapplied"]; return; }
        [reapply performClick:nil]; _smokeStep=23; return;
    }
    if (_smokeStep==23) {
        if ([_extensionImports.firstObject[@"state"] isEqual:@"failed"]) { [self smokeFinish:@"Reapplication failed"]; return; }
        if (![_extensionImports.firstObject[@"state"] isEqual:@"done"]) return;
        [_smokeChecks addObject:@"Filtered preferences remain available for explicit reapplication after a reset"];
        [self addTabURL:[NSString stringWithFormat:@"chrome-extension://%@/verify.html",identifier]]; _smokeStep=4; return;
    }
    if (_smokeStep==4) {
        if ([_activeTab.title hasPrefix:@"Import failure:"]) { [self smokeFinish:_activeTab.title]; return; }
        if (![_activeTab.title isEqual:@"Import verified"]) return;
        [_smokeChecks addObject:restore?@"Local and sync preferences survive restart without copying source account data":@"Real extension storage receives local/sync settings while preserving destination data and excluding source accounts"];
        if (!restore) {
            // A second space loads the same extension, but must not receive settings.
            SLSpace *space=[SLSpace new]; space.name=@"Import isolation"; [_spaces addObject:space];
            SLTab *tab=[SLTab new]; tab.url=[NSString stringWithFormat:@"chrome-extension://%@/verify.html?isolated",identifier]; tab.trustedInternal=YES; [space.tabs addObject:tab]; space.activeID=tab.uid;
            [self activateSpace:space]; _smokeStep=5; return;
        }
        [self smokeFinish:nil];
    }
    if (_smokeStep==5) {
        if ([_activeTab.title hasPrefix:@"Import failure:"]) { [self smokeFinish:_activeTab.title]; return; }
        if (![_activeTab.title isEqual:@"Isolation verified"]) return;
        [_smokeChecks addObject:@"Import applies only to the destination space"];
        [self activateSpace:_spaces.firstObject]; [self smokeFinish:nil];
    }
}
