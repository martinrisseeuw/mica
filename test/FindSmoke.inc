// Exercise the real application keyboard path, including Chromium child focus.
- (void)findSmokeKey:(NSString *)characters code:(unsigned short)code flags:(NSEventModifierFlags)flags {
    NSWindow *target=NSApp.keyWindow;
    NSString *text=(flags & NSEventModifierFlagShift)?characters.uppercaseString:characters;
    for (NSNumber *type in @[@(NSEventTypeKeyDown),@(NSEventTypeKeyUp)]) {
        NSEvent *event=[NSEvent keyEventWithType:(NSEventType)type.integerValue location:NSZeroPoint
            modifierFlags:flags timestamp:NSProcessInfo.processInfo.systemUptime
            windowNumber:target.windowNumber context:nil characters:text
            charactersIgnoringModifiers:text isARepeat:NO keyCode:code];
        [NSApp postEvent:event atStart:NO];
    }
}
- (void)findSmokeTick {
    // Other applications can activate while a native test is running. Resume
    // only after macOS restores this app's existing key window.
    if (!NSApp.active) { [NSApp activateIgnoringOtherApps:YES]; return; }
    static NSInteger lastStep=-1, waiting=0;
    if (lastStep!=_smokeStep) { lastStep=_smokeStep; waiting=0; }
    if (++waiting>30) { [self smokeFinish:[NSString stringWithFormat:@"Find step %ld stalled (query %@, result %@)",(long)_smokeStep,_findField.stringValue,_findCount.stringValue]]; return; }
    if (_smokeTicks%10==0) fprintf(stderr,"find: step=%ld query=%s count=%s key=%s\n",(long)_smokeStep,
        _findField.stringValue.UTF8String,_findCount.stringValue.UTF8String,NSStringFromClass(NSApp.keyWindow.class).UTF8String);
    switch (_smokeStep) {
        case 0:
            [self navigate:_smokeURL]; _smokeStep=1; break;
        case 1:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Find fixture"]) return;
            _activeTab->chrome->Focus(); _smokeStep=2; break;
        case 2:
            if (NSApp.keyWindow!=_activeTab->chrome->NativeWindow()) return;
            [self findSmokeKey:@"f" code:3 flags:NSEventModifierFlagCommand];
            // Queue typing immediately, before either event has been dispatched.
            [self findSmokeKey:@"m" code:46 flags:0]; _smokeStep=3; break;
        case 3:
            if (!_finding || _findBar.hidden) { [self smokeFinish:@"Command-F from the page did not open Find"]; return; }
            if (NSApp.keyWindow!=_window || !_findField.currentEditor || _window.firstResponder!=_findField.currentEditor) {
                fprintf(stderr,"find focus: key=%ld expected=%ld editor=%s responder=%s\n",(long)NSApp.keyWindow.windowNumber,
                    (long)_window.windowNumber,NSStringFromClass(_findField.currentEditor.class).UTF8String,NSStringFromClass(_window.firstResponder.class).UTF8String);
                [self smokeFinish:@"Command-F opened Find without moving keyboard focus out of Chromium"]; return;
            }
            [_smokeChecks addObject:@"Command-F opens and focuses Find from the Chromium page"];
            if (![_findField.stringValue isEqual:@"m"]) { [self smokeFinish:@"Typing immediately after Command-F missed the search field"]; return; }
            [_smokeChecks addObject:@"A character queued immediately after Command-F reaches the search field"];
            _smokeStep=4; break;
        case 4:
            if (![_findField.stringValue isEqual:@"m"]) { [self smokeFinish:@"Typing after Command-F missed the search field"]; return; }
            if (![_findCount.stringValue isEqual:@"1 of 3"]) return;
            [_smokeChecks addObject:@"Typing searches the page and reports the matching result count"];
            _smokeStep=5; break;
        case 5:
            if (![_findCount.stringValue isEqual:@"1 of 3"]) { [self smokeFinish:@"Typing advanced the match without a navigation key"]; return; }
            [self findSmokeKey:@"\r" code:36 flags:0]; _smokeStep=6; break;
        case 6:
            if (![_findCount.stringValue isEqual:@"2 of 3"]) return;
            [_smokeChecks addObject:@"Return advances to the next match"];
            [self findSmokeKey:@"\r" code:36 flags:NSEventModifierFlagShift]; _smokeStep=7; break;
        case 7:
            if (![_findCount.stringValue isEqual:@"1 of 3"]) return;
            [_smokeChecks addObject:@"Shift-Return moves to the previous match"];
            [self findSmokeKey:@"g" code:5 flags:NSEventModifierFlagCommand]; _smokeStep=14; break;
        case 14:
            if (![_findCount.stringValue isEqual:@"2 of 3"]) return;
            for (NSMenuItem *top in NSApp.mainMenu.itemArray) for (NSMenuItem *item in top.submenu.itemArray)
                if (item.action==@selector(findPrevious:) || item.action==@selector(findNext:)) fprintf(stderr,"find menu: %s key=%s flags=%lu enabled=%d\n",item.title.UTF8String,item.keyEquivalent.UTF8String,(unsigned long)item.keyEquivalentModifierMask,item.enabled);
            [self findSmokeKey:@"g" code:5 flags:NSEventModifierFlagCommand|NSEventModifierFlagShift]; _smokeStep=15; break;
        case 15:
            if (![_findCount.stringValue isEqual:@"1 of 3"]) return;
            [_smokeChecks addObject:@"Command-G and Shift-Command-G navigate search results"];
            _activeTab->chrome->Focus(); _smokeStep=16; break;
        case 16:
            if (NSApp.keyWindow!=_activeTab->chrome->NativeWindow()) return;
            [self findSmokeKey:@"g" code:5 flags:NSEventModifierFlagCommand]; _smokeStep=17; break;
        case 17:
            if (![_findCount.stringValue isEqual:@"2 of 3"]) return;
            [_smokeChecks addObject:@"Command-G also works while the Chromium page has focus"];
            [self findSmokeKey:@"f" code:3 flags:NSEventModifierFlagCommand]; _smokeStep=8; break;
        case 8:
            if (!NSEqualRanges(((NSTextView *)_findField.currentEditor).selectedRange,NSMakeRange(0,1))) {
                [self smokeFinish:@"Command-F did not select the existing search"]; return;
            }
            [self findSmokeKey:@"z" code:6 flags:0]; _smokeStep=9; break;
        case 9:
            if (![_findField.stringValue isEqual:@"z"] || ![_findCount.stringValue isEqual:@"0 of 0"]) return;
            [_smokeChecks addObject:@"Command-F selects the query; replacing it updates the no-match state"];
            [self findSmokeKey:@"\x1b" code:53 flags:0]; _smokeStep=10; break;
        case 10:
            if (_finding || !_findBar.hidden || NSApp.keyWindow!=_activeTab->chrome->NativeWindow()) {
                [self smokeFinish:@"Escape did not close Find and return keyboard focus to the page"]; return;
            }
            [_smokeChecks addObject:@"Escape dismisses Find and restores page keyboard focus"];
            _sidebarVisible=NO; _sidebarReveal=0; [self layout];
            [self focusAddress:nil];
            [self findSmokeKey:@"f" code:3 flags:NSEventModifierFlagCommand]; _smokeStep=11; break;
        case 11:
            if (_addressPanel.visible || !_finding || _findBar.hidden || NSApp.keyWindow!=_window || !_findField.currentEditor) {
                [self smokeFinish:@"Command-F from the address editor did not focus Find with the sidebar hidden"]; return;
            }
            [_smokeChecks addObject:@"Command-F works from the address editor with the sidebar hidden"];
            [self findSmokeKey:@"m" code:46 flags:0]; _smokeStep=12; break;
        case 12:
            if (![_findCount.stringValue isEqual:@"1 of 3"]) return;
            for (NSView *view in _findBar.subviews) if ([view.identifier isEqual:@"closeFind"]) [(NSButton *)view performClick:nil];
            _smokeStep=13; break;
        case 13:
            if (_finding || NSApp.keyWindow!=_activeTab->chrome->NativeWindow()) { [self smokeFinish:@"Close Find did not return keyboard focus to the page"]; return; }
            [_smokeChecks addObject:@"The close button dismisses Find and restores page keyboard focus"];
            [self showToolsForTab:_activeTab point:CefPoint()]; _smokeStep=18; break;
        case 18:
            if (!_activeTab.toolsReady || !_activeTab->toolsBrowser) return;
            [_window makeKeyAndOrderFront:nil]; _activeTab->toolsBrowser->GetHost()->SetFocus(true);
            _smokeStep=19; break;
        case 19: {
            NSResponder *responder=_window.firstResponder;
            if (![responder isKindOfClass:NSView.class] || ![(NSView *)responder isDescendantOf:_toolsPanel]) return;
            NSEvent *key=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:_window.windowNumber context:nil
                characters:@"f" charactersIgnoringModifiers:@"f" isARepeat:NO keyCode:3];
            if ([self handleFindShortcut:key] || _finding || _window.firstResponder!=responder) {
                [self smokeFinish:@"The page Find shortcut intercepted docked DevTools"]; return;
            }
            [_smokeChecks addObject:@"The page Find shortcut leaves docked DevTools keyboard routing intact"];
            [self applyToolsPosition:@"window"]; _smokeStep=20; break;
        }
        case 20:
            if (!_activeTab.toolsReady || !_activeTab.toolsWindow || !_activeTab->toolsBrowser) return;
            [_activeTab.toolsWindow makeKeyAndOrderFront:nil]; _activeTab->toolsBrowser->GetHost()->SetFocus(true);
            _smokeStep=21; break;
        case 21: {
            if (NSApp.keyWindow!=_activeTab.toolsWindow) return;
            NSResponder *responder=_activeTab.toolsWindow.firstResponder;
            NSEvent *key=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:_activeTab.toolsWindow.windowNumber context:nil
                characters:@"f" charactersIgnoringModifiers:@"f" isARepeat:NO keyCode:3];
            if ([self handleFindShortcut:key] || _finding || _activeTab.toolsWindow.firstResponder!=responder) {
                [self smokeFinish:@"The page Find shortcut intercepted the DevTools window"]; return;
            }
            [_smokeChecks addObject:@"The page Find shortcut leaves separate DevTools windows alone"];
            [self smokeFinish:nil]; break;
        }
    }
}
