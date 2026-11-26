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
        // A new explicit import replaces only a previous completed import of
        // the same extension in this space. Other payloads remain reapplicable.
        NSSet *selectedIDs=[NSSet setWithArray:[selected valueForKey:@"id"]];
        [controller.extensionImports filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, NSDictionary *) { return !([job[@"state"] isEqual:@"done"] && [job[@"space"] isEqual:destination.uid] && [selectedIDs containsObject:job[@"id"]]); }]];
        for (NSDictionary *entry in selected) [controller.extensionImports addObject:[@{@"id":entry[@"id"],@"name":entry[@"name"],@"space":destination.uid,@"settings":entry[@"settings"],@"state":@"waiting"} mutableCopy]];
        if (![controller saveExtensionImports]) { controller.extensionImports=before; return; }
        [controller activateSpace:destination];
        for (NSDictionary *entry in selected) [controller openChromeURL:[@"https://chromewebstore.google.com/detail/" stringByAppendingString:entry[@"id"]]];
        controller.status.stringValue=@"Finish installing and setting up each extension, then apply settings in Extensions → Import Progress.";
        [controller startExtensionImportTimer];
    }];
    [_importPanel presentForWindow:_window];
}
- (void)startExtensionImportTimer {
    if (_extensionImportTimer || _quitting) return;
    for (NSDictionary *job in _extensionImports) if ([job[@"state"] isEqual:@"waiting"] || [job[@"state"] isEqual:@"queued"]) {
        _extensionImportTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(extensionImportTick:) userInfo:nil repeats:YES]; return;
    }
}
- (void)finishExtensionImport:(BOOL)success {
    if (!_extensionImportJob) return;
    _extensionImportJob[@"state"]=success?@"done":@"failed";
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
        if (![job[@"state"] isEqual:@"waiting"] && ![job[@"state"] isEqual:@"queued"]) continue;
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
        if ([job[@"state"] isEqual:@"waiting"]) {
            job[@"state"]=@"ready";
            if ([self saveExtensionImports]) _status.stringValue=@"Extension installed. Finish its setup, then apply settings in Extensions → Import Progress.";
            else job[@"state"]=@"waiting";
            continue;
        }
        job[@"state"]=@"applying";
        if (![self saveExtensionImports]) { job[@"state"]=@"queued"; return; }
        _extensionImportJob=job; _extensionImportStarted=[NSDate date];
        SLTab *tab=[SLTab new]; tab.url=[NSString stringWithFormat:@"chrome-extension://%@/manifest.json",job[@"id"]]; tab.title=@"Importing extension settings…"; tab.trustedInternal=YES; tab.importingSettings=YES;
        _extensionImportTab=tab; [space.tabs addObject:tab]; [self loadTab:tab]; [self refresh]; return;
    }
    if (!waiting) { [_extensionImportTimer invalidate]; _extensionImportTimer=nil; }
}
- (NSArray<NSMutableDictionary *> *)applicableExtensionImports:(BOOL)reapply {
    NSMutableArray *candidates=[NSMutableArray array];
    for (NSMutableDictionary *job in _extensionImports) {
        BOOL state=reapply?[job[@"state"] isEqual:@"done"]:([job[@"state"] isEqual:@"ready"] || [job[@"state"] isEqual:@"failed"]);
        if (state && [self spaceWithID:job[@"space"]] && (SLPreferenceCount(job[@"settings"][@"local"])+SLPreferenceCount(job[@"settings"][@"sync"]))) [candidates addObject:job];
    }
    return candidates;
}
- (void)applyExtensionImportSettings:(BOOL)reapply {
    NSArray *candidates=[self applicableExtensionImports:reapply];
    NSMutableArray *previous=[NSMutableArray array];
    for (NSMutableDictionary *job in candidates) { [previous addObject:job[@"state"]]; job[@"state"]=@"queued"; }
    if ([self saveExtensionImports]) [self startExtensionImportTimer];
    else for (NSUInteger i=0;i<candidates.count;i++) candidates[i][@"state"]=previous[i];
}
- (void)showExtensionImportProgress:(id)sender {
    if (_window.attachedSheet || _quitting) return;
    NSMutableArray *lines=[NSMutableArray array];
    BOOL reapply=![self applicableExtensionImports:NO].count;
    BOOL canApply=[self applicableExtensionImports:reapply].count>0;
    NSDictionary *labels=@{@"waiting":@"Waiting for installation / enable",@"ready":@"Installed — ready to apply settings after setup",@"queued":@"Settings queued; enable extension if needed",@"applying":@"Applying settings",@"done":@"Imported",@"failed":@"Settings incomplete — retry available"};
    for (NSDictionary *job in _extensionImports) {
        SLSpace *space=[self spaceWithID:job[@"space"]];
        [lines addObject:[NSString stringWithFormat:@"%@ · %@: %@",job[@"name"],space.name ?: @"Removed space",labels[job[@"state"]]]];
    }
    NSAlert *alert=[NSAlert new]; alert.messageText=@"Extension import progress";
    alert.informativeText=lines.count?@"Finish extension setup before applying settings. You can reapply if an extension resets its preferences. Discard Imports clears saved settings and cancels pending imports; installed extensions stay installed.":@"No extensions have been imported yet.";
    if (lines.count) {
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,520,MIN(280UL,MAX(64UL,lines.count*38)))];
        scroll.hasVerticalScroller=YES; scroll.borderType=NSBezelBorder;
        NSTextView *text=[[NSTextView alloc] initWithFrame:scroll.bounds]; text.editable=NO; text.font=[NSFont systemFontOfSize:12]; text.textContainerInset=NSMakeSize(8,8); text.string=[lines componentsJoinedByString:@"\n\n"];
        text.autoresizingMask=NSViewWidthSizable; text.textContainer.widthTracksTextView=YES; scroll.documentView=text; alert.accessoryView=scroll;
    }
    [alert addButtonWithTitle:@"Done"];
    if (canApply) [alert addButtonWithTitle:reapply?@"Reapply settings":@"Apply settings"];
    if (lines.count) [alert addButtonWithTitle:@"Discard imports"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (canApply && response==NSAlertSecondButtonReturn) {
            [self applyExtensionImportSettings:reapply];
        } else if (lines.count && response==(canApply?NSAlertThirdButtonReturn:NSAlertSecondButtonReturn)) {
            if (self.extensionImportJob) [self finishExtensionImport:NO];
            NSMutableArray *before=self.extensionImports;
            self.extensionImports=[NSMutableArray array];
            if (![self saveExtensionImports]) self.extensionImports=before;
        }
    }];
}
