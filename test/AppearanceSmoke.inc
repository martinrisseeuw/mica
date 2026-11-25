// Allow one AppKit cycle after each appearance change before capturing controls.
// This changes only this disposable app's appearance, never macOS preferences.
- (BOOL)smokeWindowChromeAligned {
    NSMutableArray<NSView *> *controls=[NSMutableArray arrayWithArray:@[_sidebarButton,_backButton,_forwardButton,_reloadButton,_extensionsButton]];
    for (NSWindowButton type : {NSWindowCloseButton,NSWindowMiniaturizeButton,NSWindowZoomButton}) {
        NSButton *button=[_window standardWindowButton:type];
        if (!button || !button.action) return NO;
        [controls addObject:button];
    }
    [controls addObjectsFromArray:_extensionToolbarButtons ?: @[]];
    NSView *frame=_root.superview;
    for (NSView *view in controls) {
        if (view.hidden) continue;
        NSRect rect=[view convertRect:view.bounds toView:_root];
        if (fabs(NSMidY(rect)-28)>0.5 || !NSContainsRect(_root.bounds,rect)) return NO;
        NSPoint center=NSMakePoint(NSMidX(view.bounds),NSMidY(view.bounds));
        NSPoint hitPoint=[view convertPoint:center toView:frame.superview];
        NSView *hit=[frame hitTest:hitPoint];
        if (hit!=view && ![hit isDescendantOf:view]) return NO;
    }
    NSButton *zoom=[_window standardWindowButton:NSWindowZoomButton];
    NSRect buttons=[zoom convertRect:zoom.bounds toView:_root];
    return NSMinX(_sidebarButton.frame)-NSMaxX(buttons)>=8;
}
- (void)smokeAppearanceTick {
    if (_smokeAppearanceStage==0) {
        if (_window.appearance || NSApp.appearance || _chromeBackground.material!=NSVisualEffectMaterialSidebar || _chromeBackground.blendingMode!=NSVisualEffectBlendingModeBehindWindow || !NSEqualRects(_chromeBackground.frame,_root.bounds) || ![_root.fill isEqual:NSColor.clearColor] || ![_sidebar.fill isEqual:NSColor.clearColor] || ![((SLCanvas *)_toolbar).fill isEqual:NSColor.clearColor] || _window.opaque || ![_tabList.fill isEqual:NSColor.clearColor]) {
            [self smokeFinish:@"Browser forces an appearance or hides the native sidebar material"]; return;
        }
        NSArray *schemes=NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"];
        NSMenu *menu=NSApp.mainMenu.itemArray.firstObject.submenu;
        BOOL action=NO; for (NSMenuItem *item in menu.itemArray) if (item.action==@selector(makeDefaultBrowser:) && item.target==self) action=YES;
        if (![schemes containsObject:@"http"] || ![schemes containsObject:@"https"] || !action) { [self smokeFinish:@"Default browser registration or menu action is missing"]; return; }
        BOOL checkUpdates=NO,automaticUpdates=NO;
        for (NSMenuItem *item in menu.itemArray) {
            if (item.action==@selector(checkForUpdates:) && item.target==_updates) checkUpdates=YES;
            if (item.action==@selector(toggleAutomaticUpdates:) && item.target==_updates) automaticUpdates=YES;
        }
        if (!checkUpdates || !automaticUpdates || _updates.started) { [self smokeFinish:@"Update menus are missing or a smoke test started production update checks"]; return; }
        NSWindow *tools=[NSWindow new];
        [self windowWillEnterFullScreen:[NSNotification notificationWithName:NSWindowWillEnterFullScreenNotification object:tools]];
        if (![self smokeWindowChromeAligned]) { [self smokeFinish:@"Another window's fullscreen transition moved the browser controls"]; return; }
        [self windowWillExitFullScreen:[NSNotification notificationWithName:NSWindowWillExitFullScreenNotification object:tools]];
        if (![self smokeWindowChromeAligned]) { [self smokeFinish:@"Another window's fullscreen exit moved the browser controls"]; return; }
        _smokeAppearanceGrid=SLExtensionGrid(@[@{@"id":@"appearance-fixture",@"name":@"Example",@"image":Icon(@"puzzlepiece.extension")}],@[@"appearance-fixture"],self);
        [_smokeAppearanceGrid setFrameOrigin:NSMakePoint(-400,-400)]; [_root addSubview:_smokeAppearanceGrid];
        NSApp.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        _smokeAppearanceStage=1; return;
    }
    BOOL dark=_smokeAppearanceStage==1;
    if (SLIsDarkAppearance(_root.effectiveAppearance)!=dark || SLIsDarkAppearance(_home.effectiveAppearance)!=dark) { NSApp.appearance=nil; [self smokeFinish:@"Native browser surfaces did not inherit appearance"]; return; }
    __block BOOL contrast=NO;
    [_home.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *surface=[SLThemeColor(SLSurface) colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        NSColor *text=[SLThemeColor(SLText) colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        contrast=dark?(surface.redComponent<0.2 && text.redComponent>0.8):(surface.redComponent>0.9 && text.redComponent<0.2);
    }];
    if (!contrast) { NSApp.appearance=nil; [self smokeFinish:@"Adaptive surface or text colors have incorrect contrast"]; return; }
    NSColor *background=[[NSColor colorWithCGColor:_smokeAppearanceGrid.layer.backgroundColor] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (dark?background.redComponent>0.2:background.redComponent<0.9) { NSApp.appearance=nil; [self smokeFinish:@"Extension panel cached the wrong appearance color"]; return; }
    if (![self smokeWindowChromeAligned]) { [self smokeFinish:@"Native traffic lights and toolbar controls are misaligned or not hit-testable"]; return; }
    [self captureView:_root filename:dark?@"native-appearance-dark.png":@"native-appearance-light.png"];
    [self captureView:_root.superview filename:dark?@"native-window-dark.png":@"native-window-light.png"];
    [self captureView:_smokeAppearanceGrid filename:dark?@"extensions-appearance-dark.png":@"extensions-appearance-light.png"];
    CGFloat reveal=_sidebarReveal; _sidebarReveal=0; [self layout];
    if (NSMinX(_pageHost.frame)!=8 || NSWidth(_root.bounds)-NSMaxX(_pageHost.frame)!=8) { [self smokeFinish:@"Hidden sidebar has asymmetric viewport margins"]; return; }
    if (![self smokeWindowChromeAligned]) { [self smokeFinish:@"Collapsed toolbar overlaps native window buttons"]; return; }
    [self captureView:_root filename:dark?@"native-sidebar-hidden-dark.png":@"native-sidebar-hidden-light.png"];
    [self captureView:_root.superview filename:dark?@"native-window-hidden-dark.png":@"native-window-hidden-light.png"];
    _sidebarReveal=reveal; [self layout];
    _smokeAppearanceStage++;
    if (dark) { NSApp.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua]; return; }
    NSApp.appearance=nil; [_smokeAppearanceGrid removeFromSuperview]; _smokeAppearanceGrid=nil;
    [_smokeChecks addObject:@"Start page, sidebar and extension grid follow live light/dark appearance changes"];
    [_smokeChecks addObject:@"Sidebar, toolbar and viewport margins share one native background material"];
    [_smokeChecks addObject:@"Hidden sidebar keeps equal 8-point left and right viewport margins in both appearances"];
    [_smokeChecks addObject:@"Native window buttons and toolbar icons share a centerline and retain their hit targets with the sidebar open or closed"];
    [_smokeChecks addObject:@"Default browser menu is opt-in and the app advertises HTTP and HTTPS handling"];
    [_smokeChecks addObject:@"Update menus are wired and production update checks stay disabled in disposable browser tests"];
}
