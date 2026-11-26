// Native chrome interactions, included inside SLController.
- (void)setSidebarWidth:(CGFloat)width {
    _sidebarWidth=SLSidebarWidth(@(width));
    [self layout];
    [_window invalidateCursorRectsForView:_sidebarResizeHandle];
}
- (NSMenu *)navigationMenu {
    NSMenu *menu=[NSMenu new];
    NSArray *titles=@[@"Back",@"Forward",_activeTab.loading?@"Stop loading":@"Refresh",@"Hide sidebar"];
    NSArray *actions=@[@"goBack:",@"goForward:",@"reload:",@"toggleSidebar:"];
    NSArray *symbols=@[@"chevron.left",@"chevron.right",_activeTab.loading?@"xmark":@"arrow.clockwise",@"sidebar.left"];
    NSArray *keys=@[@"[",@"]",@"r",@"s"];
    for (NSUInteger i=0;i<titles.count;i++) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:titles[i] action:NSSelectorFromString(actions[i]) keyEquivalent:keys[i]];
        item.target=self; item.image=Icon(symbols[i]); [menu addItem:item];
    }
    return menu;
}
- (void)showNavigationMenu:(id)sender {
    [self hideAddressEditor]; [self hideExtensionMenu];
    [[self navigationMenu] popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(_navigationOverflow.frame),NSMaxY(_navigationOverflow.frame)+4) inView:_toolbar];
}
- (void)sidebarDidScroll:(NSNotification *)notification { [self positionAddressEditor]; [self positionSuggestions]; }
- (void)applicationDeactivated:(NSNotification *)notification { [self hideAddressEditor]; [self hideExtensionMenu]; }
- (void)positionAddressEditor {
    if (!_addressPanel.visible) return;
    NSRect window=[_window convertRectToScreen:[_root convertRect:_root.bounds toView:nil]];
    NSRect bounds=NSIntersectionRect(NSInsetRect(window,8,8),NSInsetRect(_window.screen.visibleFrame,8,8));
    CGFloat width=MIN(680,NSWidth(bounds)),height=148;
    CGFloat x=NSMinX(window)+(_sidebarReveal==1?_sidebarWidth+8:16);
    CGFloat top=NSMaxY(window)-64;
    if (_sidebarReveal==1) for (NSView *row in _tabList.subviews) {
        if ([row.identifier isEqual:_activeTab.uid] && !NSIsEmptyRect(row.visibleRect)) {
            NSRect anchor=[_window convertRectToScreen:[row convertRect:row.visibleRect toView:nil]];
            top=NSMaxY(anchor)+12; break;
        }
    }
    x=MAX(NSMinX(bounds),MIN(x,NSMaxX(bounds)-width));
    CGFloat y=MAX(NSMinY(bounds),MIN(top-height,NSMaxY(bounds)-height));
    [_addressPanel setFrame:NSMakeRect(x,y,width,height) display:YES];
    _addressPanel.contentView.needsLayout=YES;
    [_addressPanel.contentView layoutSubtreeIfNeeded];
}
- (void)focusAddress:(id)sender {
    if (!_activeTab || _quitting) return;
    [self hideExtensionMenu]; [self hideSuggestions];
    _address.stringValue=SLDisplayAddress(_activeTab.url);
    _addressPanel.linkCopyButton.title=@"Copy link";
    _addressPanel.linkCopyButton.enabled=_activeTab.url.length>0;
    [_window makeKeyAndOrderFront:nil];
    if (_addressPanel.parentWindow!=_window) [_window addChildWindow:_addressPanel ordered:NSWindowAbove];
    [_addressPanel orderFront:nil]; [self positionAddressEditor];
    [_addressPanel makeKeyAndOrderFront:nil]; [_addressPanel makeFirstResponder:_address]; [_address selectText:nil];
    if (!_addressMouseMonitor) {
        __weak SLController *owner=self;
        _addressMouseMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown|NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            SLController *controller=owner; if (!controller) return event;
            if (event.type==NSEventTypeKeyDown) {
                if (event.keyCode==53 && controller.addressPanel.visible) { [controller dismissAddress:nil]; return nil; }
            } else if (event.window!=controller.addressPanel && event.window!=controller.suggestionPanel) {
                [controller hideAddressEditor];
            }
            return event;
        }];
    }
}
- (void)hideAddressEditor {
    [_addressPanel makeFirstResponder:nil];
    [_addressPanel.parentWindow removeChildWindow:_addressPanel]; [_addressPanel orderOut:nil];
    _address.stringValue=SLDisplayAddress(_activeTab.url);
    if (_addressMouseMonitor) { [NSEvent removeMonitor:_addressMouseMonitor]; _addressMouseMonitor=nil; }
    [self hideSuggestions];
}
- (void)dismissAddress:(id)sender {
    [self hideAddressEditor];
    [_window makeKeyAndOrderFront:nil];
    if (_activeTab && _activeTab->chrome) _activeTab->chrome->Focus();
    else [_window makeFirstResponder:_homeAddress];
}
- (void)openAddress:(id)sender { [self submitAddress:_address]; }
- (BOOL)writePageAddressToPasteboard:(NSPasteboard *)pasteboard {
    NSString *url=SLDisplayAddress(_activeTab.url);
    if (!url.length) return NO;
    [pasteboard clearContents]; return [pasteboard setString:url forType:NSPasteboardTypeString];
}
- (void)copyPageAddress:(id)sender {
    if ([self writePageAddressToPasteboard:NSPasteboard.generalPasteboard]) _addressPanel.linkCopyButton.title=@"Copied";
}
