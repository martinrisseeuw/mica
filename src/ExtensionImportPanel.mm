#import "ExtensionImportPanel.h"
#import "ExtensionImport.h"

@interface SLImportSurface : NSView
@end
@implementation SLImportSurface
- (void)drawRect:(NSRect)dirty { [NSColor.windowBackgroundColor setFill]; NSRectFill(dirty); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
@end

@interface SLExtensionImportPanel ()
@property NSString *chromeRoot;
@property NSSet<NSString *> *installed;
@property NSArray<NSDictionary *> *profiles;
@property NSArray<NSDictionary *> *extensions;
@property NSMutableArray<NSButton *> *choices;
@property NSPopUpButton *profilePicker;
@property NSScrollView *scroll;
@property NSTextField *summary;
@property NSButton *settingsToggle;
@property NSButton *importButton;
@property NSButton *folderButton;
@property NSUInteger generation;
@property (copy) void (^completion)(NSArray<NSDictionary *> *);
@end
@implementation SLExtensionImportPanel
- (instancetype)initWithChromeRoot:(NSString *)root installed:(NSSet<NSString *> *)installed completion:(void (^)(NSArray<NSDictionary *> *))completion {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,520) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    if (!(self=[super initWithWindow:window])) return nil;
    self.chromeRoot=root; self.installed=installed; self.completion=completion; window.title=@"Import extensions from Chrome";
    window.contentView=[[SLImportSurface alloc] initWithFrame:window.contentView.bounds];
    NSView *view=window.contentView;
    NSTextField *title=[NSTextField labelWithString:@"Bring your extensions to this space"];
    title.font=[NSFont systemFontOfSize:18 weight:NSFontWeightSemibold]; title.frame=NSMakeRect(24,470,552,26); [view addSubview:title];
    NSTextField *intro=[NSTextField wrappingLabelWithString:@"Choose a Chrome profile and the extensions to reinstall. Quit Chrome first to read its latest settings."];
    intro.frame=NSMakeRect(24,422,552,40); [view addSubview:intro];
    _profilePicker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(24,380,390,30) pullsDown:NO];
    _profilePicker.target=self; _profilePicker.action=@selector(loadExtensions:); _profilePicker.accessibilityLabel=@"Chrome profile"; [view addSubview:_profilePicker];
    _folderButton=[NSButton buttonWithTitle:@"Choose folder…" target:self action:@selector(chooseFolder:)]; _folderButton.frame=NSMakeRect(430,380,146,30); [view addSubview:_folderButton];
    _scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(24,170,552,198)]; _scroll.hasVerticalScroller=YES; _scroll.borderType=NSBezelBorder; [view addSubview:_scroll];
    _settingsToggle=[NSButton checkboxWithTitle:@"Include supported settings" target:self action:@selector(selectionChanged:)];
    _settingsToggle.state=NSControlStateValueOn; _settingsToggle.frame=NSMakeRect(24,135,552,24); [view addSubview:_settingsToggle];
    NSTextField *scope=[NSTextField wrappingLabelWithString:@"Transfers recognized appearance and behavior preferences. Accounts, passwords, cookies, and unrecognized settings are excluded."];
    scope.font=[NSFont systemFontOfSize:12]; scope.textColor=NSColor.secondaryLabelColor; scope.frame=NSMakeRect(24,91,552,38); [view addSubview:scope];
    _summary=[NSTextField wrappingLabelWithString:@""]; _summary.font=[NSFont systemFontOfSize:12]; _summary.frame=NSMakeRect(24,48,552,36); [view addSubview:_summary];
    NSButton *cancel=[NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)]; cancel.keyEquivalent=@"\e"; cancel.frame=NSMakeRect(340,10,90,32); [view addSubview:cancel];
    _importButton=[NSButton buttonWithTitle:@"Continue to install" target:self action:@selector(start:)]; _importButton.keyEquivalent=@"\r"; _importButton.frame=NSMakeRect(430,10,150,32); [view addSubview:_importButton];
    [self loadProfiles]; return self;
}
- (void)presentForWindow:(NSWindow *)parent { [parent beginSheet:self.window completionHandler:nil]; }
- (void)loadProfiles {
    NSError *error=nil; _profiles=SLChromeProfiles(_chromeRoot,&error) ?: @[];
    [_profilePicker removeAllItems];
    for (NSDictionary *profile in _profiles) [_profilePicker addItemWithTitle:profile[@"name"]];
    _profilePicker.enabled=_profiles.count>0;
    if (!_profiles.count) {
        _generation++; _extensions=@[]; [self renderRows];
        _summary.stringValue=@"No Chrome profiles found. Choose Chrome’s data folder (the folder containing Local State and Default).";
    } else [self loadExtensions:nil];
}
- (void)chooseFolder:(id)sender {
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseDirectories=YES; panel.canChooseFiles=NO; panel.allowsMultipleSelection=NO;
    panel.message=@"Choose the Chrome data folder containing Local State and profile folders.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result==NSModalResponseOK) { self.chromeRoot=panel.URL.path.stringByResolvingSymlinksInPath; [self loadProfiles]; }
    }];
}
- (void)loadExtensions:(id)sender {
    NSInteger index=_profilePicker.indexOfSelectedItem;
    if (index<0 || (NSUInteger)index>=_profiles.count) return;
    NSUInteger generation=++_generation;
    NSString *path=_profiles[index][@"path"]; NSSet *installed=_installed;
    _importButton.enabled=NO; _extensions=@[]; [self renderRows]; _summary.stringValue=@"Reading extensions and supported settings…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error=nil; NSArray *extensions=SLChromeExtensions(path,installed,&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation!=self.generation) return;
            self.extensions=extensions ?: @[]; [self renderRows];
            if (error) self.summary.stringValue=error.localizedDescription;
        });
    });
}
- (void)renderRows {
    _choices=[NSMutableArray array];
    NSView *list=[[NSView alloc] initWithFrame:NSMakeRect(0,0,530,MAX(198UL,_extensions.count*58))];
    NSUInteger i=0;
    for (NSDictionary *item in _extensions) {
        CGFloat y=list.frame.size.height-(++i)*58;
        NSButton *choice=[NSButton checkboxWithTitle:item[@"name"] target:self action:@selector(selectionChanged:)];
        choice.frame=NSMakeRect(12,y+28,506,24); choice.tag=i-1; choice.identifier=item[@"id"];
        choice.enabled=[item[@"supported"] boolValue] && ![item[@"installed"] boolValue]; choice.state=NSControlStateValueOff;
        [list addSubview:choice]; [_choices addObject:choice];
        NSString *detail=[item[@"installed"] boolValue]?@"Already installed in this space — skipped":![item[@"supported"] boolValue]?@"Not from the Chrome Web Store — install manually":[item[@"warning"] length]?item[@"warning"]:[item[@"count"] unsignedIntegerValue]?[NSString stringWithFormat:@"%@ supported settings",item[@"count"]]:@"Extension only — no supported settings found";
        NSTextField *label=[NSTextField labelWithString:detail]; label.font=[NSFont systemFontOfSize:11]; label.textColor=NSColor.secondaryLabelColor; label.lineBreakMode=NSLineBreakByTruncatingTail; label.frame=NSMakeRect(32,y+7,486,18); label.toolTip=detail; [list addSubview:label];
        NSMutableArray *preview=[NSMutableArray array];
        for (NSString *area in @[@"local",@"sync"]) for (NSString *key in item[@"settings"][area]) [preview addObject:[NSString stringWithFormat:@"%@: %@ = %@",area,key,item[@"settings"][area][key]]];
        if (preview.count) choice.toolTip=[preview componentsJoinedByString:@"\n"];
    }
    _scroll.documentView=list;
    [self selectionChanged:nil];
    if (!_extensions.count) _summary.stringValue=@"No installed Chrome extensions found in this profile.";
}
- (void)selectionChanged:(id)sender {
    NSUInteger count=0,settings=0;
    for (NSButton *choice in _choices) if (choice.enabled && choice.state==NSControlStateValueOn) { count++; settings+=[_extensions[choice.tag][@"count"] unsignedIntegerValue]; }
    _importButton.enabled=count>0 && count<=20;
    _summary.stringValue=count>20?@"Select up to 20 extensions per import.":[NSString stringWithFormat:@"%lu selected · %lu supported settings. Each extension keeps its normal installation prompt.",(unsigned long)count,(unsigned long)(_settingsToggle.state==NSControlStateValueOn?settings:0)];
}
- (void)start:(id)sender {
    NSMutableArray *selected=[NSMutableArray array];
    for (NSButton *choice in _choices) if (choice.enabled && choice.state==NSControlStateValueOn) {
        NSMutableDictionary *item=[_extensions[choice.tag] mutableCopy];
        if (_settingsToggle.state!=NSControlStateValueOn) item[@"settings"]=@{};
        [selected addObject:item];
    }
    if (!selected.count || selected.count>20) return;
    _generation++; [self.window.sheetParent endSheet:self.window]; [self.window orderOut:nil];
    if (_completion) _completion(selected);
}
- (void)cancel:(id)sender {
    _generation++; [self.window.sheetParent endSheet:self.window]; [self.window orderOut:nil];
    if (_completion) _completion(@[]);
}
@end
