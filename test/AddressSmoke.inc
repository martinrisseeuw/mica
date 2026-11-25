// Native input events stay inside the disposable smoke-test window.
- (void)smokeClickAddress {
    NSPoint point=[_address convertPoint:NSMakePoint(40,NSMidY(_address.bounds)) toView:nil];
    NSEvent *(^event)(NSEventType)=^NSEvent *(NSEventType type) {
        return [NSEvent mouseEventWithType:type location:point modifierFlags:0
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber
            context:nil eventNumber:1 clickCount:1 pressure:type==NSEventTypeLeftMouseDown?1:0];
    };
    // The field editor may track through mouse-up before mouseDown returns.
    [NSApp postEvent:event(NSEventTypeLeftMouseUp) atStart:YES];
    [_window sendEvent:event(NSEventTypeLeftMouseDown)];
    [NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:NSDate.date
        inMode:NSEventTrackingRunLoopMode dequeue:YES];
}
- (BOOL)smokeAddressEditing {
    NSString *url=[_smokeURL stringByAppendingString:@"docs/a%20b?query=hello%20world&flag=&repeat=one&repeat=two#section"];
    if (![_activeTab.url isEqual:url] || ![String(_activeTab->browser->GetMainFrame()->GetURL()) isEqual:url] || ![_address.stringValue isEqual:url]) {
        [self smokeFinish:@"Address bar lost the page path, query parameters or fragment"]; return NO;
    }
    [self smokeClickAddress];
    NSTextView *editor=(NSTextView *)_address.currentEditor;
    if (!editor || ![editor.string isEqual:url] || !NSEqualRanges(editor.selectedRange,NSMakeRange(0,url.length))) {
        [self smokeFinish:[NSString stringWithFormat:@"First address-bar click did not select the complete URL (editor %@, selection %@, expected %lu, key %@, responder %@)",NSStringFromClass(editor.class),NSStringFromRange(editor.selectedRange),(unsigned long)url.length,NSStringFromClass(NSApp.keyWindow.class),NSStringFromClass(_window.firstResponder.class)]]; return NO;
    }
    NSPasteboard *clipboard=[NSPasteboard pasteboardWithUniqueName];
    NSArray *types=editor.writablePasteboardTypes;
    BOOL wrote=[editor writeSelectionToPasteboard:clipboard types:types];
    NSString *copiedURL=[clipboard stringForType:NSPasteboardTypeString];
    BOOL copied=wrote && [copiedURL isEqual:url];
    [clipboard releaseGlobally];
    if (!copied) { [self smokeFinish:[NSString stringWithFormat:@"Copying the selected address lost URL components (write %d, copied %@, types %@, selection %@)",wrote,copiedURL,types,NSStringFromRange(editor.selectedRange)]]; return NO; }
    [self smokeClickAddress];
    if (editor.selectedRange.length || editor.selectedRange.location>url.length) {
        [self smokeFinish:@"Second address-bar click did not allow caret placement"]; return NO;
    }
    NSString *edited=[url stringByReplacingCharactersInRange:editor.selectedRange withString:@"x"];
    [editor insertText:@"x" replacementRange:NSMakeRange(NSNotFound,0)];
    if (![_address.stringValue isEqual:edited]) { [self smokeFinish:@"First keystroke in the address bar was overwritten"]; return NO; }
    [self focusAddress:nil]; editor=(NSTextView *)_address.currentEditor;
    if (!NSEqualRanges(editor.selectedRange,NSMakeRange(0,url.length))) { [self smokeFinish:@"Keyboard address focus did not select the whole URL"]; return NO; }
    [editor insertText:@"replacement address" replacementRange:NSMakeRange(NSNotFound,0)];
    if (![_address.stringValue isEqual:@"replacement address"]) { [self smokeFinish:@"Typing did not replace the selected URL"]; return NO; }
    [self control:_address textView:editor doCommandBySelector:@selector(cancelOperation:)];
    if (_address.currentEditor || ![_address.stringValue isEqual:url]) { [self smokeFinish:@"Escape did not restore the complete page address"]; return NO; }
    [_smokeChecks addObject:@"Address bar preserves the full path, encoded query parameters and fragment"];
    [_smokeChecks addObject:@"First click selects and copies the complete URL without touching the system clipboard"];
    [_smokeChecks addObject:@"Second click places a caret and the first typed character is preserved"];
    [_smokeChecks addObject:@"Keyboard address focus selects the full URL, typing replaces it and Escape restores it"];
    return YES;
}
