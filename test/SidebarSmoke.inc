// Exercise the real divider callbacks with window-space drag events.
- (void)smokeDragSidebarTo:(CGFloat)width {
    NSPoint start=[_sidebarResizeHandle convertPoint:NSMakePoint(4,100) toView:nil];
    NSEvent *(^event)(NSEventType,CGFloat)=^NSEvent *(NSEventType type,CGFloat x) {
        return [NSEvent mouseEventWithType:type location:NSMakePoint(x,start.y) modifierFlags:0 timestamp:0 windowNumber:self.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    };
    CGFloat end=start.x+width-_sidebarWidth;
    [_sidebarResizeHandle mouseDown:event(NSEventTypeLeftMouseDown,start.x)];
    [_sidebarResizeHandle mouseDragged:event(NSEventTypeLeftMouseDragged,end)];
    [_sidebarResizeHandle mouseUp:event(NSEventTypeLeftMouseUp,end)];
}
- (BOOL)smokeResizableSidebar {
    [self smokeDragSidebarTo:320];
    if (_sidebarWidth!=320 || NSWidth(_sidebar.frame)!=320 || NSMinX(_pageHost.frame)!=320 || NSWidth(_tabList.frame)!=296 || ![self smokeWindowChromeAligned]) {
        [self smokeFinish:@"Dragging the sidebar did not resize the sidebar, rows and page together"]; return NO;
    }
    for (NSView *row in _tabList.subviews) if ([row isKindOfClass:SLTabButton.class]) {
        SLTabButton *tab=(SLTabButton *)row;
        if (NSWidth(tab.frame)!=296 || (tab.closeButton && !NSContainsRect(tab.bounds,tab.closeButton.frame))) {
            [self smokeFinish:@"Resizing detached a row or its close button from the sidebar edge"]; return NO;
        }
    }
    [self captureView:_root filename:@"native-sidebar-wide.png"];
    [self smokeDragSidebarTo:1000];
    if (_sidebarWidth!=360) { [self smokeFinish:@"Sidebar maximum width was not enforced"]; return NO; }
    [self smokeDragSidebarTo:1];
    NSMenu *menu=[self navigationMenu]; [menu update];
    if (_sidebarWidth!=160 || _navigationOverflow.hidden || !_backButton.hidden || !_forwardButton.hidden || !_reloadButton.hidden || !_sidebarButton.hidden || menu.numberOfItems!=4 || ![self smokeWindowChromeAligned]) {
        [self smokeFinish:@"Narrow sidebar failed to collapse all four navigation controls beside the traffic lights"]; return NO;
    }
    if (menu.itemArray[0].enabled!=_backButton.enabled || menu.itemArray[1].enabled!=_forwardButton.enabled || menu.itemArray.lastObject.action!=@selector(toggleSidebar:)) {
        [self smokeFinish:@"Navigation overflow lost actions or navigation state"]; return NO;
    }
    [self captureView:_root filename:@"native-sidebar-narrow.png"];
    [self smokeDragSidebarTo:216];
    if (!_navigationOverflow.hidden || _backButton.hidden) { [self smokeFinish:@"Widening the sidebar did not restore navigation controls"]; return NO; }
    [_smokeChecks addObject:@"Dragging resizes sidebar rows and viewport, enforces 160–360 pt bounds, and swaps navigation for overflow at narrow widths"];
    return YES;
}
