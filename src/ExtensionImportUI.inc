- (NSDictionary *)installedExtensionsInSpace:(SLSpace *)space {
    if (!space || !space.contextReady || !space->context) return @{};
    auto value=space->context->GetPreference("extensions.settings");
    if (!value || value->GetType()!=VTYPE_DICTIONARY) return @{};
    NSString *json=String(CefWriteJSON(value,JSON_WRITER_DEFAULT));
    id parsed=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return [parsed isKindOfClass:NSDictionary.class]?parsed:@{};
}
- (BOOL)saveExtensionImports {
    NSError *error=nil;
    BOOL saved=SLSaveExtensionImports(_extensionImports,[_profile stringByAppendingPathComponent:@"extension-imports.json"],&error);
    if (!saved) _status.stringValue=@"Couldn’t save the extension import. Check disk space and permissions.";
    return saved;
}
- (void)importChromeExtensions:(id)sender {
    [self hideExtensionMenu]; [self hideSuggestions];
    if (_quitting || _window.attachedSheet || !_activeSpace.contextReady) return;
    SLSpace *destination=_activeSpace;
    NSMutableSet *installed=[NSMutableSet setWithArray:[self installedExtensionsInSpace:destination].allKeys];
    for (NSDictionary *job in _extensionImports) if ([job[@"space"] isEqual:destination.uid] && ![job[@"state"] isEqual:@"done"]) [installed addObject:job[@"id"]];
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Google/Chrome"];
    __weak SLController *owner=self;
    _importPanel=[[SLExtensionImportPanel alloc] initWithChromeRoot:root installed:installed completion:^(NSArray<NSDictionary *> *selected) {
        SLController *controller=owner; if (!controller || controller.quitting) return;
        controller.importPanel=nil;
        if (!selected.count || destination.removing || ![controller.spaces containsObject:destination]) return;
        NSDictionary *alreadyInstalled=[controller installedExtensionsInSpace:destination];
        selected=[selected filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *) { return !alreadyInstalled[item[@"id"]]; }]];
        if (!selected.count) { controller.status.stringValue=@"These extensions are already installed. Their settings were kept."; return; }
        NSMutableArray *before=[controller.extensionImports mutableCopy];
        // Completed entries are only a progress summary, never another import.
        [controller.extensionImports filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, NSDictionary *) { return ![job[@"state"] isEqual:@"done"]; }]];
        for (NSDictionary *entry in selected) [controller.extensionImports addObject:[@{@"id":entry[@"id"],@"name":entry[@"name"],@"space":destination.uid,@"settings":entry[@"settings"],@"state":@"waiting"} mutableCopy]];
        if (![controller saveExtensionImports]) { controller.extensionImports=before; return; }
        [controller activateSpace:destination];
        for (NSDictionary *entry in selected) [controller openChromeURL:[@"https://chromewebstore.google.com/detail/" stringByAppendingString:entry[@"id"]]];
        controller.status.stringValue=@"Install each selected extension in its store tab. Supported settings will follow automatically.";
        [controller startExtensionImportTimer];
    }];
    [_importPanel presentForWindow:_window];
}
- (void)startExtensionImportTimer {
    if (_extensionImportTimer || _quitting) return;
    for (NSDictionary *job in _extensionImports) if ([job[@"state"] isEqual:@"waiting"]) {
        _extensionImportTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(extensionImportTick:) userInfo:nil repeats:YES]; return;
    }
}
- (void)finishExtensionImport:(BOOL)success {
    if (!_extensionImportJob) return;
    _extensionImportJob[@"state"]=success?@"done":@"failed";
    if (success) _extensionImportJob[@"settings"]=@{}; // No need to retain imported values.
    if (_extensionImportTab && _extensionImportTab->importBridge) { _extensionImportTab->importBridge->Cancel(); _extensionImportTab->importBridge=nullptr; }
    SLTab *tab=_extensionImportTab; _extensionImportTab=nil; _extensionImportJob=nil; _extensionImportStarted=nil;
    if (tab && !tab.closing && [self spaceForTab:tab]) [self closeTab:tab sleep:NO];
    if ([self saveExtensionImports]) _status.stringValue=success?@"Extension settings imported. Sign in separately if needed.":@"Settings weren’t fully imported. See Extensions → Import Progress to retry.";
}
- (void)extensionImportTick:(NSTimer *)timer {
    if (_quitting) return;
    if (_extensionImportJob) {
        SLTab *tab=_extensionImportTab;
        if (!tab || tab.closing || ![self spaceForTab:tab] || [self spaceForTab:tab].removing || tab.error || -[_extensionImportStarted timeIntervalSinceNow]>20) { [self finishExtensionImport:NO]; return; }
        if (!tab->browser || tab.loading || tab->importBridge) return;
        NSString *expected=[NSString stringWithFormat:@"chrome-extension://%@/manifest.json",_extensionImportJob[@"id"]];
        if (![String(tab->browser->GetMainFrame()->GetURL()) isEqual:expected]) { [self finishExtensionImport:NO]; return; }
        NSString *script=SLExtensionSettingsScript(_extensionImportJob[@"id"],_extensionImportJob[@"settings"]);
        __weak SLController *owner=self; NSMutableDictionary *job=_extensionImportJob;
        tab->importBridge=new SLExtensionImportBridge;
        tab->importBridge->Start(tab->browser,script,^(BOOL success) { if (owner.extensionImportJob==job) [owner finishExtensionImport:success]; });
        return;
    }
    BOOL waiting=NO; NSMutableDictionary *catalogs=[NSMutableDictionary dictionary];
    for (NSMutableDictionary *job in _extensionImports) {
        if (![job[@"state"] isEqual:@"waiting"]) continue;
        SLSpace *space=[self spaceWithID:job[@"space"]];
        if (!space) { job[@"state"]=@"failed"; [self saveExtensionImports]; continue; }
        waiting=YES;
        if (!space.contextReady) { [self ensureContext:space]; continue; }
        if (!catalogs[space.uid]) catalogs[space.uid]=[self installedExtensionsInSpace:space];
        NSDictionary *entry=catalogs[space.uid][job[@"id"]];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        // Current Chromium records enabled state through disable_reasons;
        // older profiles may additionally contain the numeric state field.
        id reasons=entry[@"disable_reasons"];
        if ((entry[@"state"] && ![entry[@"state"] isEqual:@1]) || ([reasons respondsToSelector:@selector(count)] && [reasons count])) continue;
        if (!SLPreferenceCount(job[@"settings"][@"local"]) && !SLPreferenceCount(job[@"settings"][@"sync"])) { job[@"state"]=@"done"; [self saveExtensionImports]; continue; }
        job[@"state"]=@"applying";
        if (![self saveExtensionImports]) { job[@"state"]=@"waiting"; return; }
        _extensionImportJob=job; _extensionImportStarted=[NSDate date];
        SLTab *tab=[SLTab new]; tab.url=[NSString stringWithFormat:@"chrome-extension://%@/manifest.json",job[@"id"]]; tab.title=@"Importing extension settings…"; tab.trustedInternal=YES; tab.importingSettings=YES;
        _extensionImportTab=tab; [space.tabs addObject:tab]; [self loadTab:tab]; [self refresh]; return;
    }
    if (!waiting) { [_extensionImportTimer invalidate]; _extensionImportTimer=nil; }
}
- (void)showExtensionImportProgress:(id)sender {
    if (_window.attachedSheet || _quitting) return;
    NSMutableArray *lines=[NSMutableArray array]; BOOL unfinished=NO, failed=NO;
    NSDictionary *labels=@{@"waiting":@"Waiting for installation / enable",@"applying":@"Applying settings",@"done":@"Imported",@"failed":@"Settings incomplete — retry available"};
    for (NSDictionary *job in _extensionImports) {
        SLSpace *space=[self spaceWithID:job[@"space"]];
        [lines addObject:[NSString stringWithFormat:@"%@ · %@: %@",job[@"name"],space.name ?: @"Removed space",labels[job[@"state"]]]];
        unfinished|=![job[@"state"] isEqual:@"done"]; failed|=[job[@"state"] isEqual:@"failed"];
    }
    NSAlert *alert=[NSAlert new]; alert.messageText=@"Extension import progress";
    alert.informativeText=lines.count?@"Complete installation in each store tab. Settings are applied in the destination space.":@"No extensions have been imported yet.";
    if (lines.count) {
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,520,MIN(280UL,MAX(64UL,lines.count*38)))];
        scroll.hasVerticalScroller=YES; scroll.borderType=NSBezelBorder;
        NSTextView *text=[[NSTextView alloc] initWithFrame:scroll.bounds]; text.editable=NO; text.font=[NSFont systemFontOfSize:12]; text.textContainerInset=NSMakeSize(8,8); text.string=[lines componentsJoinedByString:@"\n\n"];
        text.autoresizingMask=NSViewWidthSizable; text.textContainer.widthTracksTextView=YES; scroll.documentView=text; alert.accessoryView=scroll;
    }
    [alert addButtonWithTitle:@"Done"];
    if (unfinished) [alert addButtonWithTitle:@"Cancel pending imports"];
    if (failed) [alert addButtonWithTitle:@"Retry settings"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response==NSAlertSecondButtonReturn) {
            if (self.extensionImportJob) [self finishExtensionImport:NO];
            NSMutableArray *before=[self.extensionImports mutableCopy];
            [self.extensionImports filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, NSDictionary *) { return [job[@"state"] isEqual:@"done"]; }]];
            if (![self saveExtensionImports]) self.extensionImports=before;
        } else if (failed && response==NSAlertThirdButtonReturn) {
            NSMutableArray *retried=[NSMutableArray array];
            for (NSMutableDictionary *job in self.extensionImports) if ([job[@"state"] isEqual:@"failed"] && [self spaceWithID:job[@"space"]]) { job[@"state"]=@"waiting"; [retried addObject:job]; }
            if ([self saveExtensionImports]) [self startExtensionImportTimer];
            else for (NSMutableDictionary *job in retried) job[@"state"]=@"failed";
        }
    }];
}
