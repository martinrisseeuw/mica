- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    // This notification arrives on the first edit, not on focus. Replacing
    // the value here would discard the user's first keystroke or paste.
    if (notification.object==_address) _nativeAddressEditing=YES;
}
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object!=_address) return;
    __weak SLController *owner=self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!owner.address.currentEditor) { owner.nativeAddressEditing=NO; [owner hideSuggestions]; [owner layout]; }
    });
}
// Native address suggestions. Included inside SLController's implementation.
- (SLSpace *)spaceForTab:(SLTab *)tab {
    for (SLSpace *space in _spaces) if ([space.tabs containsObject:tab]) return space;
    return nil;
}
- (void)recordVisit:(SLTab *)tab {
    if (!tab.error && !tab.closing) [[self spaceForTab:tab].history visit:tab.url title:tab.title];
}
- (NSString *)faviconPath:(NSString *)url space:(SLSpace *)space {
    NSURLComponents *parts=[NSURLComponents componentsWithString:SLHistoryURL(url) ?: @""];
    if (!parts.host.length || !space) return nil;
    parts.path=@""; parts.query=nil; parts.fragment=nil;
    NSData *bytes=[parts.string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,digest);
    NSMutableString *key=[NSMutableString string]; for (unsigned char value : digest) [key appendFormat:@"%02x",value];
    return [_profile stringByAppendingPathComponent:[NSString stringWithFormat:@"Favicons/%@/%@.png",space.uid,key]];
}
- (void)faviconChanged:(SLTab *)tab urls:(const std::vector<CefString> &)urls {
    if (!tab->browser || tab.closing || urls.empty()) return;
    NSString *url=nil;
    for (const auto &candidate : urls) {
        NSString *value=String(candidate); NSString *scheme=[NSURL URLWithString:value].scheme.lowercaseString;
        if ([@[@"http",@"https",@"data"] containsObject:scheme]) { url=value; break; }
    }
    if (!url || [url isEqual:tab.faviconURL]) return;
    tab.faviconURL=url; NSUInteger generation=tab.navigationGeneration;
    NSString *page=tab.url; SLSpace *space=[self spaceForTab:tab]; __weak SLController *owner=self; __weak SLTab *weakTab=tab;
    tab->browser->GetHost()->DownloadImage(url.UTF8String,true,32,false,new FaviconDownload(^(NSData *data) {
        SLTab *target=weakTab; SLController *strongOwner=owner;
        if (!target || !strongOwner || target.closing || target.navigationGeneration!=generation || ![target.url isEqual:page]) return;
        NSImage *image=[[NSImage alloc] initWithData:data]; if (!image) return;
        image.size=NSMakeSize(18,18); target.favicon=image;
        NSString *path=[strongOwner faviconPath:page space:space];
        if (path) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
            [data writeToFile:path options:NSDataWritingAtomic error:nil];
        }
        [strongOwner refresh];
    }));
}
- (void)hideSuggestions {
    [_window removeChildWindow:_suggestionPanel]; [_suggestionPanel orderOut:nil];
    _suggestions=nil; _suggestionField=nil; _typedQuery=nil;
    if (_suggestionMouseMonitor) { [NSEvent removeMonitor:_suggestionMouseMonitor]; _suggestionMouseMonitor=nil; }
}
- (void)positionSuggestions {
    if (!_suggestionPanel.visible || !_suggestionField) return;
    NSRect anchor=[_suggestionField convertRect:_suggestionField.bounds toView:nil];
    anchor=[_window convertRectToScreen:anchor];
    CGFloat width=MIN(820,MAX(anchor.size.width,480));
    NSRect screen=_window.screen.visibleFrame;
    CGFloat x=MAX(NSMinX(screen)+8,MIN(anchor.origin.x-12,NSMaxX(screen)-width-8));
    CGFloat height=12+_suggestions.count*60+36;
    CGFloat y=MAX(NSMinY(screen)+8,NSMinY(anchor)-height-8);
    [_suggestionPanel setFrame:NSMakeRect(x,y,width,height) display:YES];
}
- (void)updateSuggestions:(NSTextField *)field complete:(BOOL)complete {
    NSTextView *editor=(NSTextView *)field.currentEditor;
    if (!editor || editor.hasMarkedText) { [self hideSuggestions]; return; }
    _suggestionField=field; _typedQuery=field.stringValue; _suggestionIndex=0;
    NSMutableArray *tabs=[NSMutableArray array];
    for (SLTab *tab in _activeSpace.tabs) if (!tab.closing) [tabs addObject:@{@"id":tab.uid,@"url":tab.url,@"title":tab.title}];
    NSMutableArray *matches=[[_activeSpace.history suggestions:_typedQuery tabs:tabs] mutableCopy];
    if (_typedQuery.length) {
        NSString *resolved=SLResolveAddress(_typedQuery);
        if (resolved) [matches addObject:@{@"url":resolved,@"title":[NSString stringWithFormat:[resolved hasPrefix:@"https://duckduckgo.com/?q="]?@"Search for “%@”":@"Open %@",_typedQuery],@"direct":@YES}];
    }
    if (!matches.count) { [self hideSuggestions]; return; }
    _suggestions=matches;
    if (complete && editor.selectedRange.length==0 && editor.selectedRange.location==_typedQuery.length && ![matches.firstObject[@"direct"] boolValue]) {
        NSString *completion=SLCompletion(_typedQuery,matches.firstObject[@"url"]);
        if (completion) {
            // Native selection makes subsequent typing replace only the suffix.
            field.stringValue=completion; editor.string=completion;
            editor.selectedRange=NSMakeRange(_typedQuery.length,completion.length-_typedQuery.length);
        }
    }
    if (!_suggestionPanel) {
        _suggestionPanel=[[NSPanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        _suggestionPanel.appearance=_window.appearance;
        _suggestionPanel.releasedWhenClosed=NO; _suggestionPanel.opaque=NO; _suggestionPanel.backgroundColor=NSColor.clearColor;
        _suggestionPanel.hasShadow=YES; _suggestionPanel.hidesOnDeactivate=YES;
    }
    [_window addChildWindow:_suggestionPanel ordered:NSWindowAbove]; [_suggestionPanel orderFront:nil];
    [self positionSuggestions]; [self renderSuggestions];
    if (!_suggestionMouseMonitor) {
        __weak SLController *owner=self;
        _suggestionMouseMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *event) {
            SLController *controller=owner;
            if (controller && event.window!=controller.suggestionPanel) [controller hideSuggestions];
            return event;
        }];
    }
}
- (void)renderSuggestions {
    CGFloat width=_suggestionPanel.frame.size.width;
    SLCanvas *canvas=[[SLCanvas alloc] initWithFrame:NSMakeRect(0,0,width,_suggestionPanel.frame.size.height)];
    canvas.fill=SLThemeColor(SLSurface); canvas.wantsLayer=YES; canvas.layer.cornerRadius=10; canvas.layer.borderWidth=1;
    [canvas.effectiveAppearance performAsCurrentDrawingAppearance:^{ canvas.layer.borderColor=SLThemeColor(SLPopoverBorder).CGColor; }];
    _suggestionPanel.contentView=canvas;
    NSInteger index=0;
    for (NSDictionary *entry in _suggestions) {
        CGFloat y=6+index*60;
        SLCanvas *row=[[SLCanvas alloc] initWithFrame:NSMakeRect(6,y,width-12,58)];
        row.fill=SLThemeColor(index==_suggestionIndex?SLSelection:SLSurface); row.wantsLayer=YES; row.layer.cornerRadius=6;
        [canvas addSubview:row];
        BOOL direct=[entry[@"direct"] boolValue];
        NSImage *favicon=direct?Icon(@"magnifyingglass"):[[NSImage alloc] initWithContentsOfFile:[self faviconPath:entry[@"url"] space:_activeSpace]];
        NSImageView *icon=[NSImageView imageViewWithImage:favicon ?: Icon(@"globe")]; icon.frame=NSMakeRect(14,20,18,18); [row addSubview:icon];
        NSTextField *title=[self label:entry[@"title"] size:14 weight:index==_suggestionIndex?NSFontWeightSemibold:NSFontWeightRegular];
        title.lineBreakMode=NSLineBreakByTruncatingTail; title.frame=NSMakeRect(48,direct?19:10,width-220,20); [row addSubview:title];
        if (!direct) {
            NSTextField *url=[self label:entry[@"url"] size:12 weight:NSFontWeightRegular]; url.textColor=SLThemeColor(SLSecondaryText); url.lineBreakMode=NSLineBreakByTruncatingMiddle; url.frame=NSMakeRect(48,31,width-220,18); [row addSubview:url];
        }
        NSString *hint=entry[@"tabID"]?@"Switch to tab":(direct?@"↵":@"History");
        NSTextField *trailing=[self label:hint size:12 weight:NSFontWeightRegular]; trailing.textColor=SLThemeColor(SLSecondaryText); trailing.alignment=NSTextAlignmentRight; trailing.frame=NSMakeRect(width-152,20,116,18); [row addSubview:trailing];
        NSButton *button=[[NSButton alloc] initWithFrame:row.bounds]; button.title=@""; button.bordered=NO; button.target=self; button.action=@selector(suggestionClicked:); button.tag=index;
        button.accessibilityLabel=[NSString stringWithFormat:@"%@, %@, %@",entry[@"title"],entry[@"url"],hint]; [row addSubview:button];
        index++;
    }
    NSTextField *footer=[self label:@"↑↓  Navigate       ↵  Open       Esc  Dismiss" size:12 weight:NSFontWeightRegular];
    footer.textColor=SLThemeColor(SLSecondaryText); footer.frame=NSMakeRect(18,14+index*60,width-36,20); [canvas addSubview:footer];
}
- (void)suggestionClicked:(NSButton *)button { _suggestionIndex=button.tag; [self acceptSuggestion]; }
- (void)acceptSuggestion {
    if (_suggestionIndex<0 || _suggestionIndex>=(NSInteger)_suggestions.count) return;
    NSDictionary *choice=_suggestions[_suggestionIndex]; [self hideSuggestions];
    SLTab *existing=choice[@"tabID"]?[self tabWithID:choice[@"tabID"]]:nil;
    if (existing && [_activeSpace.tabs containsObject:existing]) [self selectTab:existing]; else [self navigate:choice[@"url"]];
}
- (void)clearHistory:(id)sender {
    [_activeSpace.history clear]; [self hideSuggestions];
}
