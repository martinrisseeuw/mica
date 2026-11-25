// Included inside SLController. Pins are saved rows; a live page is optional.
- (void)renderTabRow:(SLTab *)tab y:(CGFloat)y indent:(CGFloat)indent {
    SLTabButton *button=[[SLTabButton alloc] initWithFrame:NSMakeRect(0,y,192,36)];
    NSString *title=tab.title.length?tab.title:@"New tab";
    button.title=title; button.indent=indent;
    button.font=[NSFont systemFontOfSize:13 weight:tab==_activeTab?NSFontWeightSemibold:NSFontWeightRegular];
    button.image=tab.favicon ?: Icon(SLIsExtensionsPage(tab.url)?@"puzzlepiece.extension":(tab.url.length?@"globe":@"plus"));
    button.imagePosition=NSImageOnly; button.bordered=NO;
    button.target=self; button.action=@selector(tabClicked:); button.identifier=tab.uid;
    button.toolTip=tab.pinned?[NSString stringWithFormat:@"%@\n%@",title,tab.pinURL ?: tab.url]:tab.url;
    button.selectedTab=tab==_activeTab; button.accessibilityLabel=title;
    button.menu=[self tabMenu:tab]; [_tabList addSubview:button];
    if (!tab.pinned || tab->browser || tab.creating) {
        NSButton *close=[self button:@"xmark" label:[NSString stringWithFormat:tab.pinned?@"Close %@ (keep pin)":@"Close %@",title] action:@selector(closeTabButton:)];
        close.identifier=tab.uid; close.frame=NSMakeRect(164,6,22,24); close.hidden=tab!=_activeTab;
        button.closeButton=close; [button addSubview:close];
    }
}
- (void)renderSidebar {
    for (NSView *view in [_tabList.subviews copy]) [view removeFromSuperview];
    CGFloat y=0; BOOL hasPins=NO;
    for (SLTab *tab in _activeSpace.tabs) if (tab.pinned && !tab.folderID.length) {
        [self renderTabRow:tab y:y indent:0]; y+=40; hasPins=YES;
    }
    for (NSDictionary *folder in _activeSpace.folders) {
        BOOL collapsed=[folder[@"collapsed"] boolValue];
        SLTabButton *row=[[SLTabButton alloc] initWithFrame:NSMakeRect(0,y,192,36)];
        row.title=folder[@"name"]; row.image=Icon(@"folder");
        row.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]; row.bordered=NO;
        row.target=self; row.action=@selector(toggleFolder:); row.identifier=folder[@"id"];
        row.accessibilityLabel=[NSString stringWithFormat:@"%@, %@ folder",row.title,collapsed?@"collapsed":@"expanded"];
        NSImageView *chevron=[NSImageView imageViewWithImage:Icon(collapsed?@"chevron.right":@"chevron.down")];
        chevron.contentTintColor=SLThemeColor(SLSecondaryText); chevron.frame=NSMakeRect(171,12,9,12); [row addSubview:chevron];
        NSMenu *menu=[NSMenu new];
        for (NSArray *action in @[@[@"Rename Folder…",@"renameFolder:"],@[@"Remove Folder (Keep Pins)",@"removeFolder:"]]) {
            NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:action[0] action:NSSelectorFromString(action[1]) keyEquivalent:@""];
            item.target=self; item.representedObject=folder[@"id"]; [menu addItem:item];
        }
        row.menu=menu; [_tabList addSubview:row]; y+=40; hasPins=YES;
        if (!collapsed) for (SLTab *tab in _activeSpace.tabs) if (tab.pinned && [tab.folderID isEqual:folder[@"id"]]) {
            [self renderTabRow:tab y:y indent:16]; y+=40;
        }
    }
    if (hasPins) {
        NSBox *line=[[NSBox alloc] initWithFrame:NSMakeRect(10,y+8,172,1)]; line.boxType=NSBoxSeparator;
        [_tabList addSubview:line]; y+=24;
    }
    NSButton *newTab=[NSButton buttonWithTitle:@"  New tab" image:Icon(@"plus") target:self action:@selector(newTab:)];
    newTab.frame=NSMakeRect(8,y,176,36); newTab.bordered=NO; newTab.alignment=NSTextAlignmentLeft;
    newTab.font=[NSFont systemFontOfSize:13]; newTab.contentTintColor=SLThemeColor(SLSecondaryText);
    newTab.toolTip=@"New tab (⌘T)"; newTab.accessibilityLabel=@"New tab"; [_tabList addSubview:newTab]; y+=44;
    for (SLTab *tab in _activeSpace.tabs) if (!tab.pinned) { [self renderTabRow:tab y:y indent:0]; y+=40; }
    _tabList.frame=NSMakeRect(0,0,192,MAX(y+8,_tabScroll.contentView.bounds.size.height));
}
- (NSMutableDictionary *)folderWithID:(NSString *)uid {
    for (NSMutableDictionary *folder in _activeSpace.folders) if ([folder[@"id"] isEqual:uid]) return folder;
    return nil;
}
- (void)toggleFolder:(NSButton *)sender {
    NSMutableDictionary *folder=[self folderWithID:sender.identifier];
    if (folder) { folder[@"collapsed"]=@(![folder[@"collapsed"] boolValue]); [self refresh]; }
}
- (void)addFolderMenuTo:(NSMenu *)menu tab:(SLTab *)tab {
    if (!tab.url.length) return;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *move=[[NSMenuItem alloc] initWithTitle:@"Move to Folder" action:nil keyEquivalent:@""];
    move.submenu=[NSMenu new]; [menu addItem:move];
    for (NSDictionary *folder in _activeSpace.folders) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:folder[@"name"] action:@selector(movePinToFolder:) keyEquivalent:@""];
        item.target=self; item.representedObject=@{@"tab":tab.uid,@"folder":folder[@"id"]};
        item.state=[tab.folderID isEqual:folder[@"id"]]?NSControlStateValueOn:NSControlStateValueOff; [move.submenu addItem:item];
    }
    if (tab.folderID.length) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Outside Folder" action:@selector(movePinToFolder:) keyEquivalent:@""];
        item.target=self; item.representedObject=@{@"tab":tab.uid,@"folder":@""}; [move.submenu addItem:item];
    }
    if (move.submenu.numberOfItems) [move.submenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *create=[[NSMenuItem alloc] initWithTitle:@"New Folder…" action:@selector(newFolder:) keyEquivalent:@""];
    create.target=self; create.representedObject=tab.uid; [move.submenu addItem:create];
    if (tab.pinned) {
        NSMenuItem *update=[[NSMenuItem alloc] initWithTitle:@"Save Current URL to Pin" action:@selector(updatePin:) keyEquivalent:@""];
        update.target=self; update.representedObject=tab.uid; [menu addItem:update];
    }
}
- (void)movePinToFolder:(NSMenuItem *)sender {
    SLTab *tab=[self tabWithID:sender.representedObject[@"tab"]];
    NSString *uid=sender.representedObject[@"folder"];
    if (!tab || [self spaceForTab:tab]!=_activeSpace || (uid.length && ![self folderWithID:uid])) return;
    if (!tab.pinned) [self setPinned:YES tab:tab];
    tab.folderID=uid.length?uid:nil;
    NSMutableDictionary *folder=[self folderWithID:uid]; if (folder) folder[@"collapsed"]=@NO;
    [self refresh];
}
- (void)updatePin:(NSMenuItem *)sender {
    SLTab *tab=[self tabWithID:sender.representedObject];
    if (tab.pinned) { tab.pinURL=tab.url; tab.pinTitle=tab.title; [self refresh]; }
}
- (void)newFolder:(id)sender {
    if (_activeSpace.folders.count>=100) return;
    SLSpace *space=_activeSpace;
    SLTab *tab=[sender isKindOfClass:NSMenuItem.class]?[self tabWithID:[sender representedObject]]:nil;
    NSAlert *alert=[NSAlert new]; alert.messageText=@"New folder";
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,280,26)]; field.stringValue=@"New folder"; alert.accessoryView=field;
    [alert addButtonWithTitle:@"Create"]; [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        NSString *name=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (result!=NSAlertFirstButtonReturn || !name.length) return;
        NSMutableDictionary *folder=[@{@"id":SLNewID(),@"name":[name substringToIndex:MIN(name.length,48UL)],@"collapsed":@NO} mutableCopy];
        [space.folders addObject:folder];
        if (tab && [space.tabs containsObject:tab]) { if (!tab.pinned) [self setPinned:YES tab:tab]; tab.folderID=folder[@"id"]; }
        [self refresh];
    }];
    [alert.window makeFirstResponder:field]; [field selectText:nil];
}
- (void)renameFolder:(NSMenuItem *)sender {
    NSMutableDictionary *folder=[self folderWithID:sender.representedObject]; if (!folder) return;
    NSAlert *alert=[NSAlert new]; alert.messageText=@"Rename folder";
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,280,26)]; field.stringValue=folder[@"name"]; alert.accessoryView=field;
    [alert addButtonWithTitle:@"Save"]; [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        NSString *name=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (result==NSAlertFirstButtonReturn && name.length) { folder[@"name"]=[name substringToIndex:MIN(name.length,48UL)]; [self refresh]; }
    }];
    [alert.window makeFirstResponder:field]; [field selectText:nil];
}
- (void)removeFolder:(NSMenuItem *)sender {
    NSMutableDictionary *folder=[self folderWithID:sender.representedObject]; if (!folder) return;
    for (SLTab *tab in _activeSpace.tabs) if ([tab.folderID isEqual:folder[@"id"]]) tab.folderID=nil;
    [_activeSpace.folders removeObject:folder]; [self refresh];
}
