// Native input events stay inside the disposable smoke-test window.
- (void)smokeClickAddress {
    NSPoint point=[_address convertPoint:NSMakePoint(40,NSMidY(_address.bounds)) toView:nil];
    NSEvent *(^event)(NSEventType)=^NSEvent *(NSEventType type) {
        return [NSEvent mouseEventWithType:type location:point modifierFlags:0
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.address.window.windowNumber
            context:nil eventNumber:1 clickCount:1 pressure:type==NSEventTypeLeftMouseDown?1:0];
    };
    // Deliver to the native hit-tested view: a background test window otherwise
    // consumes its first click for application activation instead of editing.
    NSView *target=[_address.window.contentView hitTest:point];
    // The field editor may track through mouse-up before mouseDown returns.
    [NSApp postEvent:event(NSEventTypeLeftMouseUp) atStart:YES];
    [target mouseDown:event(NSEventTypeLeftMouseDown)];
    [NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:NSDate.date
        inMode:NSEventTrackingRunLoopMode dequeue:YES];
}
- (BOOL)smokeAddressEditing {
    NSString *url=[_smokeURL stringByAppendingString:@"docs/a%20b?query=hello%20world&flag=&repeat=one&repeat=two#section"];
    if (![_activeTab.url isEqual:url] || ![String(_activeTab->browser->GetMainFrame()->GetURL()) isEqual:url] || ![_address.stringValue isEqual:url]) {
        [self smokeFinish:@"Address bar lost the page path, query parameters or fragment"]; return NO;
    }
    if (_addressPanel.visible || NSMinY(_pageHost.frame)!=8) { [self smokeFinish:@"Browsing still shows an address bar or reserves the old top bar"]; return NO; }
    NSButton *selected=nil;
    for (NSView *row in _tabList.subviews) if ([row.identifier isEqual:_activeTab.uid]) selected=(NSButton *)row;
    [selected performClick:nil];
    [self captureView:_addressPanel.contentView filename:@"tab-address-editor.png"];
    NSTextView *editor=(NSTextView *)_address.currentEditor;
    if (!_addressPanel.visible || !editor || ![editor.string isEqual:url] || !NSEqualRanges(editor.selectedRange,NSMakeRange(0,url.length))) {
        [self smokeFinish:[NSString stringWithFormat:@"First address-bar click did not select the complete URL (editor %@, selection %@, expected %lu, key %@, responder %@)",NSStringFromClass(editor.class),NSStringFromRange(editor.selectedRange),(unsigned long)url.length,NSStringFromClass(NSApp.keyWindow.class),NSStringFromClass(_window.firstResponder.class)]]; return NO;
    }
    NSPasteboard *clipboard=[NSPasteboard pasteboardWithUniqueName];
    if (![self writePageAddressToPasteboard:clipboard] || ![[clipboard stringForType:NSPasteboardTypeString] isEqual:url]) {
        [clipboard releaseGlobally]; [self smokeFinish:@"Copy link did not preserve the complete current page URL"]; return NO;
    }
    NSArray *types=editor.writablePasteboardTypes;
    BOOL wrote=[editor writeSelectionToPasteboard:clipboard types:types];
    NSString *copiedURL=[clipboard stringForType:NSPasteboardTypeString];
    BOOL copied=wrote && [copiedURL isEqual:url];
    [clipboard releaseGlobally];
    if (!copied) { [self smokeFinish:[NSString stringWithFormat:@"Copying the selected address lost URL components (write %d, copied %@, types %@, selection %@)",wrote,copiedURL,types,NSStringFromRange(editor.selectedRange)]]; return NO; }
    [self smokeClickAddress];
    if (editor.selectedRange.length || editor.selectedRange.location>url.length) {
        [self smokeFinish:[NSString stringWithFormat:@"Second address click did not allow caret placement (selection %@, field %@, key %@)",NSStringFromRange(editor.selectedRange),NSStringFromRect(_address.frame),NSStringFromClass(NSApp.keyWindow.class)]]; return NO;
    }
    NSString *edited=[url stringByReplacingCharactersInRange:editor.selectedRange withString:@"x"];
    [editor insertText:@"x" replacementRange:NSMakeRange(NSNotFound,0)];
    if (![_address.stringValue isEqual:edited]) { [self smokeFinish:@"First keystroke in the address bar was overwritten"]; return NO; }
    [self focusAddress:nil]; editor=(NSTextView *)_address.currentEditor;
    if (!NSEqualRanges(editor.selectedRange,NSMakeRange(0,url.length))) { [self smokeFinish:@"Keyboard address focus did not select the whole URL"]; return NO; }
    [editor insertText:@"replacement address" replacementRange:NSMakeRange(NSNotFound,0)];
    if (![_address.stringValue isEqual:@"replacement address"]) { [self smokeFinish:@"Typing did not replace the selected URL"]; return NO; }
    [self control:_address textView:editor doCommandBySelector:@selector(cancelOperation:)];
    if (_addressPanel.visible || _address.currentEditor || ![_address.stringValue isEqual:url]) { [self smokeFinish:@"Escape did not restore the complete page address"]; return NO; }
    [self focusAddress:nil];
    [self captureView:_addressPanel.contentView filename:@"tab-address-editor.png"];
    NSPoint point=[_spacePicker convertPoint:NSMakePoint(4,4) toView:nil];
    NSEvent *outside=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:0 windowNumber:_window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:1];
    [NSApp sendEvent:outside];
    if (_addressPanel.visible) { [self smokeFinish:@"Clicking outside left the address editor open"]; return NO; }
    [self focusAddress:nil];
    SLTab *original=_activeTab; [self newTab:nil]; SLTab *empty=_activeTab;
    [self selectTab:original];
    if (_addressPanel.visible) { [self smokeFinish:@"Switching tabs opened or retained the address editor"]; return NO; }
    [self closeTab:empty sleep:NO];
    _sidebarReveal=0; [self layout];
    NSEvent *shortcut=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:_window.windowNumber context:nil characters:@"l" charactersIgnoringModifiers:@"l" isARepeat:NO keyCode:37];
    if (![NSApp.mainMenu performKeyEquivalent:shortcut] || !_addressPanel.visible || !_address.currentEditor) { [self smokeFinish:@"Command-L did not open the editor with the sidebar hidden"]; return NO; }
    [self hideAddressEditor]; _sidebarReveal=1;
    NSRect windowFrame=_window.frame;
    [self setSidebarWidth:360];
    [_window setFrame:NSMakeRect(windowFrame.origin.x,windowFrame.origin.y,760,500) display:YES];
    [self focusAddress:nil];
    NSRect bounds=[_window convertRectToScreen:[_root convertRect:NSInsetRect(_root.bounds,8,8) toView:nil]];
    if (!NSContainsRect(bounds,_addressPanel.frame)) { [self smokeFinish:@"Address editor escaped the minimum-size window with a wide sidebar"]; return NO; }
    [self captureView:_addressPanel.contentView filename:@"tab-address-editor-small.png"];
    [self hideAddressEditor]; [_window setFrame:windowFrame display:YES]; [self setSidebarWidth:216];
    [_smokeChecks addObject:@"Clicking the selected tab opens the URL editor; switching tabs and clicking outside dismiss it"];
    [_smokeChecks addObject:@"Copy link preserves the complete page URL without changing navigation or the system clipboard"];
    [_smokeChecks addObject:@"Address bar preserves the full path, encoded query parameters and fragment"];
    [_smokeChecks addObject:@"First click selects and copies the complete URL without touching the system clipboard"];
    [_smokeChecks addObject:@"Second click places a caret and the first typed character is preserved"];
    [_smokeChecks addObject:@"Keyboard address focus selects the full URL, typing replaces it and Escape restores it"];
    [_smokeChecks addObject:@"Command-L works with the sidebar hidden; the editor fits the minimum window with a wide sidebar"];
    [self focusAddress:nil];
    editor=(NSTextView *)_address.currentEditor;
    NSString *destination=[_smokeURL stringByAppendingString:@"address-go?retained=yes#fragment"];
    [editor insertText:destination replacementRange:NSMakeRange(NSNotFound,0)];
    if (!_suggestionPanel.visible || _suggestionPanel.parentWindow!=_addressPanel || NSIntersectsRect(_suggestionPanel.frame,_addressPanel.frame)) { [self smokeFinish:@"Address suggestions overlap or detach from the editor"]; return NO; }
    NSUInteger tabCount=_activeSpace.tabs.count;
    NSButton *go=nil;
    for (NSView *view in _addressPanel.contentView.subviews) if ([view isKindOfClass:NSButton.class] && [(NSButton *)view action]==@selector(openAddress:)) go=(NSButton *)view;
    [go performClick:nil];
    if (!go || _addressPanel.visible || _activeTab!=original || _activeSpace.tabs.count!=tabCount || ![_activeTab.url isEqual:destination]) { [self smokeFinish:@"Go did not open the edited URL in the same tab"]; return NO; }
    return YES;
}
