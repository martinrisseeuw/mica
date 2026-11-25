- (NSArray<NSDictionary *> *)extensionActions {
    if (!_activeSpace->context) return @[];
    auto value=_activeSpace->context->GetPreference("extensions.settings");
    if (!value || value->GetType()!=VTYPE_DICTIONARY) return @[];
    NSString *json=String(CefWriteJSON(value,JSON_WRITER_DEFAULT));
    NSDictionary *settings=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSMutableArray *actions=[NSMutableArray array];
    for (NSString *identifier in settings) {
        NSDictionary *entry=settings[identifier], *manifest=entry[@"manifest"];
        NSString *path=entry[@"path"];
        NSString *root=path.isAbsolutePath?path:[String(_activeSpace->context->GetCachePath()) stringByAppendingPathComponent:[@"Extensions" stringByAppendingPathComponent:path ?: @""]];
        if (!manifest && path.length) {
            NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"manifest.json"]];
            id parsed=data.length<2*1024*1024 && data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            if ([parsed isKindOfClass:NSDictionary.class]) manifest=parsed;
        }
        if ([entry[@"disable_reasons"] count] || !manifest || manifest[@"theme"]) continue;
        NSDictionary *action=manifest[@"action"] ?: manifest[@"browser_action"] ?: manifest[@"page_action"];
        if (!action) continue;
        NSString *name=manifest[@"name"] ?: identifier;
        if ([identifier isEqual:@"aeblfdkhhhdcdjpifhhbdiojplfjncoa"]) name=@"1Password";
        if ([name hasPrefix:@"__MSG_"]) name=identifier;
        NSMutableArray *labels=[NSMutableArray arrayWithObject:manifest[@"name"] ?: name];
        if ([action[@"default_title"] length]) [labels addObject:action[@"default_title"]];
        NSMutableDictionary *item=[@{@"id":identifier,@"name":name,@"labels":labels} mutableCopy];
        id actionIcons=action[@"default_icon"];
        NSString *(^iconPath)(id)=^NSString *(id icons) {
            if ([icons isKindOfClass:NSString.class]) return icons;
            if ([icons isKindOfClass:NSDictionary.class]) for (NSString *size in @[@"32",@"24",@"48",@"38",@"19",@"16",@"64",@"128"]) if ([icons[size] isKindOfClass:NSString.class]) return icons[size];
            return nil;
        };
        NSString *icon=iconPath(actionIcons) ?: iconPath(manifest[@"icons"]);
        if (icon.length && !icon.isAbsolutePath && ![icon.pathComponents containsObject:@".."]) {
            NSString *file=[[root stringByAppendingPathComponent:icon] stringByResolvingSymlinksInPath];
            if ([file hasPrefix:[[root stringByResolvingSymlinksInPath] stringByAppendingString:@"/"]]) {
                NSImage *image=[[NSImage alloc] initWithContentsOfFile:file];
                if (image) { image.size=NSMakeSize(20,20); item[@"image"]=image; }
            }
        }
        [actions addObject:item];
    }
    return [actions sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
}
- (NSArray<NSString *> *)pinnedExtensionIDs {
    if (!_activeSpace || !_activeSpace->context || !_activeSpace.contextReady) return @[];
    auto value=_activeSpace->context->GetPreference("extensions.pinned_extensions");
    if (!value || value->GetType()!=VTYPE_LIST) return @[];
    auto list=value->GetList(); NSMutableArray *ids=[NSMutableArray array];
    for (size_t i=0;i<list->GetSize();i++) if (list->GetType(i)==VTYPE_STRING) [ids addObject:String(list->GetString(i))];
    return ids;
}
- (void)scheduleExtensionRefresh {
    if (_extensionRefreshScheduled || _quitting) return;
    _extensionRefreshScheduled=YES; __weak SLController *owner=self;
    dispatch_async(dispatch_get_main_queue(), ^{
        owner.extensionRefreshScheduled=NO;
        if (!owner || owner.quitting) return;
        [owner refreshExtensionToolbar];
        if (owner.extensionPanel.visible) [owner renderExtensionMenu];
    });
}
- (void)refreshExtensionToolbar {
    for (NSButton *button in _extensionToolbarButtons) [button removeFromSuperview];
    NSMutableDictionary *catalog=[NSMutableDictionary dictionary];
    for (NSDictionary *action in [self extensionActions]) catalog[action[@"id"]]=action;
    NSMutableArray *buttons=[NSMutableArray array];
    for (NSString *identifier in [self pinnedExtensionIDs]) {
        NSDictionary *action=catalog[identifier]; if (!action) continue;
        NSButton *button=[self button:@"puzzlepiece.extension" label:[@"Open " stringByAppendingString:action[@"name"]] action:@selector(openExtensionButton:)];
        button.identifier=identifier; button.image=action[@"image"] ?: button.image; button.contentTintColor=nil;
        NSMenu *menu=[NSMenu new]; NSMenuItem *unpin=[[NSMenuItem alloc] initWithTitle:@"Unpin from toolbar" action:@selector(unpinExtensionFromMenu:) keyEquivalent:@""]; unpin.target=self; unpin.representedObject=identifier; [menu addItem:unpin]; button.menu=menu;
        [_toolbar addSubview:button]; [buttons addObject:button];
    }
    _extensionToolbarButtons=buttons; if (_window) [self layout];
}
- (void)unpinExtensionFromMenu:(NSMenuItem *)item {
    if (![[self pinnedExtensionIDs] containsObject:item.representedObject]) return;
    NSButton *button=[NSButton new]; button.identifier=item.representedObject; [self toggleExtensionPin:button];
}
- (void)toggleExtensionPin:(NSButton *)sender {
    NSString *identifier=sender.identifier; BOOL known=NO;
    for (NSDictionary *item in [self extensionActions]) if ([item[@"id"] isEqual:identifier]) known=YES;
    if (!known) return;
    NSMutableArray *pins=[[self pinnedExtensionIDs] mutableCopy];
    if ([pins containsObject:identifier]) [pins removeObject:identifier]; else [pins addObject:identifier];
    auto list=CefListValue::Create(); for (NSUInteger i=0;i<pins.count;i++) list->SetString(i,[pins[i] UTF8String]);
    auto value=CefValue::Create(); value->SetList(list); CefString error;
    if (!_activeSpace->context->SetPreference("extensions.pinned_extensions",value,error)) { _status.stringValue=@"Couldn’t update extension pins."; return; }
    [self refreshExtensionToolbar];
    if (_extensionPanel.visible) [self renderExtensionMenu];
}
- (void)renderExtensionMenu {
    NSButton *focused=[_extensionPanel.firstResponder isKindOfClass:NSButton.class]?(NSButton *)_extensionPanel.firstResponder:nil;
    NSString *identifier=focused.identifier; SEL action=focused.action;
    _extensionPanel.contentView=SLExtensionGrid([self extensionActions],[self pinnedExtensionIDs],self);
    [_extensionPanel setContentSize:_extensionPanel.contentView.frame.size]; [self positionExtensionMenu];
    NSButton *replacement=identifier?SLExtensionControl(_extensionPanel.contentView,identifier,action):nil;
    if (replacement) [_extensionPanel makeFirstResponder:replacement];
}
- (void)positionExtensionMenu {
    if (!_extensionPanel.visible) return;
    NSRect anchor=[_window convertRectToScreen:[_extensionsButton convertRect:_extensionsButton.bounds toView:nil]];
    NSRect screen=_window.screen.visibleFrame;
    CGFloat width=_extensionPanel.frame.size.width,height=_extensionPanel.frame.size.height;
    CGFloat x=MAX(NSMinX(screen)+8,MIN(NSMaxX(anchor)+4-width,NSMaxX(screen)-width-8));
    CGFloat y=MAX(NSMinY(screen)+8,NSMinY(anchor)-height-9);
    [_extensionPanel setFrame:NSMakeRect(x,y,width,height) display:YES];
}
- (void)hideExtensionMenu {
    [_window removeChildWindow:_extensionPanel]; [_extensionPanel orderOut:nil];
    if (_extensionMouseMonitor) { [NSEvent removeMonitor:_extensionMouseMonitor]; _extensionMouseMonitor=nil; }
}
- (void)showExtensionMenu:(id)sender {
    [self hideSuggestions];
    if (_extensionPanel.visible) { [self hideExtensionMenu]; return; }
    if (!_activeSpace.contextReady) { _pendingExtensionMenuSpaceID=_activeSpace.uid; [self ensureContext:_activeSpace]; return; }
    if (!_extensionPanel) {
        _extensionPanel=[[SLExtensionPanel alloc] initWithContentRect:NSMakeRect(0,0,312,180) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        _extensionPanel.actionTarget=self; _extensionPanel.opaque=NO; _extensionPanel.backgroundColor=NSColor.clearColor; _extensionPanel.hasShadow=YES; _extensionPanel.hidesOnDeactivate=YES;
        _extensionPanel.appearance=nil;
    }
    [self renderExtensionMenu]; [_window addChildWindow:_extensionPanel ordered:NSWindowAbove]; [_extensionPanel makeKeyAndOrderFront:nil]; [self positionExtensionMenu]; [_extensionPanel selectNextKeyView:nil];
    if (!_extensionMouseMonitor) {
        __weak SLController *owner=self;
        _extensionMouseMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown|NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            SLController *controller=owner;
            if (event.type==NSEventTypeKeyDown && event.keyCode==53 && controller.extensionPanel.visible) { [controller hideExtensionMenu]; return nil; }
            if (event.type!=NSEventTypeKeyDown && event.window!=controller.extensionPanel) {
                BOOL puzzle=event.window==controller.window && NSPointInRect([controller.extensionsButton convertPoint:event.locationInWindow fromView:nil],controller.extensionsButton.bounds);
                if (!puzzle) [controller hideExtensionMenu];
            }
            return event;
        }];
    }
}
- (void)openExtensionButton:(NSButton *)sender {
    NSMenuItem *item=[NSMenuItem new]; item.representedObject=sender.identifier; [self activateExtension:item];
}
- (void)activateExtension:(NSMenuItem *)sender {
    [self hideExtensionMenu];
    NSString *identifier=sender.representedObject;
    NSDictionary *selected=nil;
    for (NSDictionary *item in [self extensionActions]) if ([item[@"id"] isEqual:identifier]) selected=item;
    if (!selected) return;
    if (!_activeTab->browser || !_activeTab->chrome) {
        [self navigate:@"mica://extensions/"]; _activeTab.pendingExtensionID=identifier; return;
    }
    if (!_activeTab->chrome || !_activeTab->chrome->TriggerExtensionAction(_activeSpace->context,identifier,selected[@"labels"])) {
        _status.stringValue=@"Couldn’t open this extension. Try reloading the page.";
    }
}
- (void)showExtensions:(id)sender {
    [self hideExtensionMenu];
    for (SLTab *tab in _activeSpace.tabs) if (SLIsExtensionsPage(tab.url)) { [self selectTab:tab]; return; }
    if (!_activeTab.url.length && !_activeTab->browser) [self navigate:@"mica://extensions/"];
    else [self addTabURL:@"mica://extensions/"];
}
- (void)openChromeURL:(NSString *)url {
    if (_quitting) return;
    [self hideExtensionMenu]; [self hideSuggestions];
    if ([url isEqual:@"chrome://newtab/"]) [self newTab:nil];
    else [self addTabURL:url];
}
- (void)installOnePassword:(id)sender { [self openChromeURL:@"https://chromewebstore.google.com/detail/1password-%E2%80%93-password-manager/aeblfdkhhhdcdjpifhhbdiojplfjncoa"]; }
- (void)manageChromeExtensions:(id)sender { [self showExtensions:sender]; }
- (void)browseExtensions:(id)sender { [self openChromeURL:@"https://chromewebstore.google.com/"]; }
