#import "Browser.h"
#import "Appearance.h"
#import "WindowChrome.h"
#import "BrowserControls.h"
#import "Updates.h"
#import "../test/UpdateProbe.h"
#import "DefaultBrowser.h"
#import "Model.h"
#import "History.h"
#import "StartPage.h"
#import "ExtensionPanel.h"
#import "ExtensionImportPanel.h"
#import "ExtensionImport.h"
#include "ExtensionImportBridge.h"
#include "ChromeExtensions.h"
#include "include/cef_id_mappers.h"
#import <CommonCrypto/CommonDigest.h>
#import "ShieldRequest.h"
#include "include/cef_registration.h"
#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_browser.h"
#include "include/cef_request_context.h"
#include "include/cef_parser.h"
#include <map>
#include <set>
#include "include/wrapper/cef_helpers.h"

static NSString *String(const CefString &s) { return [NSString stringWithUTF8String:s.ToString().c_str()] ?: @""; }
static NSString *SLDisplayAddress(NSString *url) {
    return SLPublicURL(url ?: @"");
}
static NSImage *Icon(NSString *name) { return [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]; }

class ToolsConnection;
class ChromeTabHost;

@interface SLTab : NSObject { @public CefRefPtr<CefBrowser> browser, toolsBrowser; CefRefPtr<CefRegistration> testRegistration; CefRefPtr<ToolsConnection> toolsConnection; CefRefPtr<ChromeTabHost> chrome; CefRefPtr<SLExtensionImportBridge> importBridge; }
@property NSString *uid;
@property NSString *url;
@property NSString *title;
@property NSString *error;
@property NSImage *favicon;
@property NSString *faviconURL;
@property NSUInteger navigationGeneration;
@property BOOL trustedInternal;
@property BOOL importingSettings;
@property BOOL popup;
@property BOOL rehosting;
@property BOOL pinned;
@property NSString *pinURL;
@property NSString *pinTitle;
@property NSString *folderID;
@property BOOL loading;
@property BOOL creating;
@property BOOL pendingTools;
@property NSString *pendingExtensionID;
@property BOOL closing;
@property BOOL sleeping;
@property NSView *container;
@property NSView *toolsContainer;
@property BOOL toolsCreating;
@property BOOL toolsClosing;
@property BOOL toolsReady;
@property BOOL reopenTools;
@property BOOL windowTools;
@property NSWindow *toolsWindow;
@property NSInteger toolsMessages;
@property BOOL toolsVerified;
@property BOOL toolsPausedTest;
@property NSString *toolsTestState;
@property NSPoint inspectPoint;
@property BOOL inspectPending;
@end
@interface SLSpace : NSObject { @public CefRefPtr<CefRequestContext> context; CefRefPtr<CefRegistration> extensionSettingsWatch, extensionPinsWatch; }
@property NSString *uid;
@property NSString *name;
@property SLHistory *history;
@property BOOL contextReady;
@property BOOL removing;
@property NSString *activeID;
@property NSMutableArray<SLTab *> *tabs;
@property NSMutableArray<NSMutableDictionary *> *folders;
@end
@implementation SLSpace
- (instancetype)init { if ((self=[super init])) { _uid=SLNewID(); _name=@"Space"; _tabs=[NSMutableArray array]; _folders=[NSMutableArray array]; } return self; }
@end
@interface SLCanvas : NSView
@property NSColor *fill;
@end
@implementation SLCanvas
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) self.clipsToBounds=YES;
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; if (self.layer.borderWidth) [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ self.layer.borderColor=SLThemeColor(SLPopoverBorder).CGColor; }]; }
- (void)drawRect:(NSRect)rect {
    if ([_fill isEqual:NSColor.clearColor]) return;
    [(_fill ?: NSColor.windowBackgroundColor) setFill]; NSRectFill(NSIntersectionRect(rect,self.bounds));
}
- (BOOL)mouseDownCanMoveWindow { return YES; }
@end
@interface SLTabButton : NSButton
@property BOOL selectedTab;
@property BOOL hovered;
@property BOOL iconOnly;
@property NSButton *closeButton;
@property CGFloat indent;
@end
@implementation SLTabButton
- (BOOL)allowsVibrancy { return NO; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in [self.trackingAreas copy]) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event { _hovered=YES; _closeButton.hidden=NO; self.needsDisplay=YES; }
- (void)mouseExited:(NSEvent *)event { _hovered=NO; _closeButton.hidden=!_selectedTab; self.needsDisplay=YES; }
- (void)drawRect:(NSRect)rect {
    if (_selectedTab || _hovered) { [SLThemeColor(_selectedTab?SLSelection:SLHover) setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill]; }
    NSRect iconRect=NSMakeRect(_iconOnly?(self.bounds.size.width-20)/2:10+_indent, (self.bounds.size.height-18)/2,18,18);
    SLDrawIcon(self.image,iconRect,YES);
    if (!_iconOnly) {
        NSMutableParagraphStyle *style=[NSMutableParagraphStyle new]; style.lineBreakMode=NSLineBreakByTruncatingTail;
        [self.title drawInRect:NSMakeRect(36+_indent,9,self.bounds.size.width-66-_indent,18) withAttributes:@{NSFontAttributeName:self.font,NSForegroundColorAttributeName:SLThemeColor(SLText),NSParagraphStyleAttributeName:style}];
    }
    if (self.window.firstResponder==self) { [SLThemeColor(SLSecondaryText) setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:6 yRadius:6] stroke]; }
}
@end

@interface SLController () <SLExtensionActions, SLAddressActions, NSMenuItemValidation>
@property NSString *profile;
@property NSWindow *window;
@property SLWindowChrome *windowChrome;
@property SLUpdates *updates;
@property BOOL testMode;
@property SLCanvas *root;
@property SLChromeMaterial *chromeBackground;
@property SLCanvas *sidebar;
@property NSView *toolbar;
@property NSView *utilityBar;
@property NSButton *navigationOverflow;
@property SLSidebarResizeHandle *sidebarResizeHandle;
@property (nonatomic) CGFloat sidebarWidth;
@property CGFloat resizeStartWidth;
@property BOOL resizingSidebar;
@property SLAddressPanel *addressPanel;
@property id addressMouseMonitor;
@property NSView *pageHost;
@property NSView *home;
@property SLCanvas *findBar;
@property NSSearchField *findField;
@property NSTextField *findCount;
@property NSTextField *address;
@property NSTextField *homeAddress;
@property NSTextField *status;
@property NSButton *backButton;
@property NSButton *forwardButton;
@property NSButton *reloadButton;
@property NSButton *pinButton;
@property NSButton *toolsButton;
@property NSButton *sidebarButton;
@property NSButton *shieldButton;
@property NSButton *extensionsButton;
@property NSArray<NSButton *> *extensionToolbarButtons;
@property SLExtensionPanel *extensionPanel;
@property id extensionMouseMonitor;
@property BOOL extensionRefreshScheduled;
@property SLExtensionImportPanel *importPanel;
@property NSMutableArray<NSMutableDictionary *> *extensionImports;
@property NSTimer *extensionImportTimer;
@property SLTab *extensionImportTab;
@property NSMutableDictionary *extensionImportJob;
@property NSDate *extensionImportStarted;
@property SLViewportBackdrop *viewportBackdrop;
@property CGFloat sidebarReveal;
@property NSTimer *sidebarAnimation;
@property CFTimeInterval sidebarAnimationStart;
@property CGFloat sidebarAnimationFrom;
@property NSPanel *suggestionPanel;
@property NSArray<NSDictionary *> *suggestions;
@property NSInteger suggestionIndex;
@property NSString *typedQuery;
@property (weak) NSTextField *suggestionField;
@property BOOL suppressCompletion;
@property id suggestionMouseMonitor;
@property SLCanvas *toolsPanel;
@property NSString *toolsPosition;
@property BOOL adblockEnabled;
@property NSMutableArray<NSString *> *pausedHosts;
@property NSPopUpButton *spacePicker;
@property NSButton *spaceActionsButton;
@property NSScrollView *tabScroll;
@property SLCanvas *tabList;
@property NSMutableArray<SLSpace *> *spaces;
@property SLSpace *activeSpace;
@property SLTab *activeTab;
@property NSMutableArray<SLTab *> *closingTabs;
@property NSMutableArray<NSDictionary *> *closedTabs;
@property BOOL sidebarVisible;
@property BOOL quitting;
@property BOOL settingDefaultBrowser;
@property NSMutableArray<NSString *> *pendingExternalURLs;
@property BOOL quitScheduled;
@property BOOL finding;
@property NSInteger devToolsCount;
@property NSMutableArray<SLTab *> *chromeWindows;
@property NSInteger chromeCreating;
@property NSTimer *saveTimer;
@property NSTimer *smokeTimer;
@property NSInteger smokeStep;
@property NSInteger smokeTicks;
@property BOOL smokeCaptured;
@property NSString *smokeURL;
@property NSString *smokePath;
@property NSMutableArray<NSString *> *smokeChecks;
@property NSString *smokePopupExtension;
@property BOOL extensionScriptReady;
@property BOOL extensionScriptLoaded;
@property BOOL smokePopupPrepared;
@property NSInteger smokeExtensionDownloads;
@property BOOL smokeDownloadSettled;
@property NSString *smokeParkedPin;
@property NSUInteger smokeAppearanceStage;
@property NSView *smokeAppearanceGrid;
@property NSMenu *smokeSpaceMenu;
@property NSString *smokeSpaceID;
@property NSUInteger smokeExternalTabCount;
@property NSString *smokeExternalOriginalID;
@property NSString *pendingExtensionMenuSpaceID;
- (void)refresh;
- (void)hideAddressEditor;
- (void)positionAddressEditor;
- (void)setSidebarWidth:(CGFloat)width;
- (NSMenu *)navigationMenu;
- (void)layout;
- (void)save;
- (void)loadTab:(SLTab *)tab;
- (void)browserCreated:(SLTab *)tab;
- (void)rehostChromeTab:(SLTab *)tab url:(NSString *)url;
- (void)navigate:(NSString *)url;
- (void)addTabURL:(NSString *)url;
- (void)selectTab:(SLTab *)tab;
- (void)tabReadyToClose:(SLTab *)tab;
- (void)tabClosed:(SLTab *)tab;
- (void)closeCancelled:(SLTab *)tab;
- (void)showToolsForTab:(SLTab *)tab point:(CefPoint)point;
- (void)applyToolsPosition:(NSString *)position;
- (void)syncToolsDockSide:(SLTab *)tab;
- (void)finishQuitIfReady;
- (void)closeTools:(SLTab *)tab;
- (void)showExtensionMenu:(id)sender;
- (void)activateExtension:(NSMenuItem *)sender;
- (void)refreshExtensionToolbar;
- (void)scheduleExtensionRefresh;
- (void)finishSpaceRemoval;
- (void)toolsClosed:(SLTab *)tab;
- (void)inspectInTools:(SLTab *)tab;
- (void)focusNewTab;
- (SLSpace *)spaceForTab:(SLTab *)tab;
- (void)recordVisit:(SLTab *)tab;
- (void)faviconChanged:(SLTab *)tab urls:(const std::vector<CefString> &)urls;
- (void)hideSuggestions;
- (void)openChromeURL:(NSString *)url;
- (void)ensureContext:(SLSpace *)space;
- (void)importChromeExtensions:(id)sender;
- (void)extensionImportTick:(NSTimer *)timer;
- (void)finishExtensionImport:(BOOL)success;
- (void)startExtensionImportTimer;
- (void)renderSuggestions;
- (BOOL)handleChromeCommand:(int)command tab:(SLTab *)tab;
- (NSString *)faviconPath:(NSString *)url space:(SLSpace *)space;
@end

#include "ToolsConnection.h"
#include "ChromeTabHost.h"
class ExtensionPreferences final : public CefPreferenceObserver {
public:
    explicit ExtensionPreferences(SLController *owner) : owner_(owner) {}
    void OnPreferenceChanged(const CefString &) override { [owner_ scheduleExtensionRefresh]; }
private:
    __weak SLController *owner_;
    IMPLEMENT_REFCOUNTING(ExtensionPreferences);
};
class QuitMessageLoop final : public CefTask {
public:
    void Execute() override { CefQuitMessageLoop(); }
private:
    IMPLEMENT_REFCOUNTING(QuitMessageLoop);
};
@implementation SLTab
- (instancetype)init { if ((self = [super init])) { _uid=SLNewID(); _url=@""; _title=@"New tab"; } return self; }
@end
#include "DockClient.h"
#include "../test/ToolsCapture.h"
#include "../test/ExtensionProbe.h"

class FaviconDownload final : public CefDownloadImageCallback {
public:
    explicit FaviconDownload(void (^completion)(NSData *)) : completion_([completion copy]) {}
    void OnDownloadImageFinished(const CefString &, int, CefRefPtr<CefImage> image) override {
        if (!image || image->IsEmpty()) return;
        int width=0,height=0; auto png=image->GetAsPNG(1.0,true,width,height);
        if (!png || png->GetSize()>256*1024) return;
        NSMutableData *data=[NSMutableData dataWithLength:png->GetSize()]; png->GetData(data.mutableBytes,data.length,0);
        completion_(data);
    }
private:
    void (^completion_)(NSData *);
    IMPLEMENT_REFCOUNTING(FaviconDownload);
};

class TabClient final : public CefClient, public CefLifeSpanHandler, public CefDisplayHandler,
 public CefLoadHandler, public CefRequestHandler, public CefContextMenuHandler,
 public CefDownloadHandler, public CefFindHandler, public CefJSDialogHandler, public CefCommandHandler {
public:
    TabClient(SLController *owner, SLTab *tab) : owner_(owner), tab_(tab) {}
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
    CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
    CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
    CefRefPtr<CefCommandHandler> GetCommandHandler() override { return this; }
    bool OnChromeCommand(CefRefPtr<CefBrowser> source, int command, cef_window_open_disposition_t) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) return false;
        return [owner_ handleChromeCommand:command tab:tab_];
    }
    void OnAfterCreated(CefRefPtr<CefBrowser> b) override {
        CEF_REQUIRE_UI_THREAD();
        if (owner_.smokePath.length) fprintf(stderr,"created browser=%d popup=%d reused=%d\n",b->GetIdentifier(),b->IsPopup(),tab_ && tab_->browser!=nullptr);
        if (!CefBrowserView::GetForBrowser(b)) {
            // Chromium can create its own window for extension onboarding.
            // Keep it invisible and route its destination into a Mica view.
            SLTab *pending=[SLTab new]; pending.rehosting=YES; pending.trustedInternal=YES; pending->browser=b;
            tabs_[b->GetIdentifier()]=pending; [owner_.chromeWindows addObject:pending];
            NSView *view=(__bridge NSView *)b->GetHost()->GetWindowHandle();
            BOOL shared=NO;
            for (SLSpace *space in owner_.spaces) for (SLTab *tab in space.tabs)
                if (tab->chrome && tab->chrome->NativeWindow()==view.window) shared=YES;
            if (!shared) { view.window.alphaValue=0; [view.window orderOut:nil]; }
            NSString *url=String(b->GetMainFrame()->GetURL());
            if (url.length && ![url isEqual:@"about:blank"]) {
                __weak SLController *owner=owner_;
                dispatch_async(dispatch_get_main_queue(),^{ [owner rehostChromeTab:pending url:url]; });
            }
            return;
        }
        if (!tab_ || tab_->browser) {
            SLSpace *space=nil;
            for (SLSpace *candidate in owner_.spaces) if (candidate->context && candidate->context->IsSame(b->GetHost()->GetRequestContext())) { space=candidate; break; }
            if (!space) { rejected_.insert(b->GetIdentifier()); b->GetHost()->CloseBrowser(true); return; }
            tab_=[SLTab new]; tab_.popup=YES; tab_.trustedInternal=YES;
            [space.tabs addObject:tab_];
            tab_->chrome=new ChromeTabHost(owner_,tab_);
        }
        tab_->browser = b;
        tabs_[b->GetIdentifier()]=tab_;
        tab_.creating=NO;
        __weak SLController *owner=owner_; SLTab *tab=tab_;
        dispatch_async(dispatch_get_main_queue(), ^{ [owner browserCreated:tab]; });
    }
    void OnTitleChange(CefRefPtr<CefBrowser> source, const CefString &title) override {
        SLTab *tab_=FindTab(source);
        if (!tab_ || tab_.rehosting) return;
        tab_.title = String(title).length ? String(title) : tab_.url;
        [[owner_ spaceForTab:tab_].history updateTitle:tab_.title forURL:tab_.url];
        [owner_ refresh];
    }
    void OnAddressChange(CefRefPtr<CefBrowser> source, CefRefPtr<CefFrame> frame, const CefString &url) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) return;
        if (!frame->IsMain()) return;
        if (tab_.rehosting) {
            NSString *address=String(url); if (!address.length || [address isEqual:@"about:blank"]) return;
            __weak SLController *owner=owner_; SLTab *pending=tab_;
            dispatch_async(dispatch_get_main_queue(),^{ [owner rehostChromeTab:pending url:address]; });
            return;
        }
        if (![tab_.url isEqual:String(url)]) { tab_.favicon=nil; tab_.faviconURL=nil; }
        tab_.url = SLPublicURL(String(url));
        tab_.trustedInternal=SLIsExtensionsPage(tab_.url) || SLTrustedExtensionURL(tab_.url);
        [owner_ refresh];
    }
    void OnLoadingStateChange(CefRefPtr<CefBrowser> source, bool loading, bool, bool) override {
        SLTab *tab_=FindTab(source);
        if (!tab_ || tab_.rehosting) return;
        tab_.loading = loading;
        [owner_ refresh];
    }
    void OnLoadStart(CefRefPtr<CefBrowser> source, CefRefPtr<CefFrame> frame, TransitionType) override {
        SLTab *tab_=FindTab(source);
        if (!tab_ || tab_.rehosting) return;
        if (frame->IsMain()) { tab_.error=nil; tab_.faviconURL=nil; tab_.navigationGeneration++; [owner_ refresh]; }
    }
    void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int status) override {
        SLTab *tab_=FindTab(browser);
        if (!tab_ || tab_.rehosting) return;
        if (frame->IsMain() && tab_.pendingExtensionID.length) {
            NSString *identifier=tab_.pendingExtensionID; tab_.pendingExtensionID=nil;
            __weak SLController *owner=owner_;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!owner || owner.activeTab!=tab_ || tab_.closing) return;
                NSMenuItem *item=[NSMenuItem new]; item.representedObject=identifier; [owner activateExtension:item];
            });
        }
        if (frame->IsMain() && status>=200 && status<400) [owner_ recordVisit:tab_];
        if (!SLHistoryURL(String(frame->GetURL())) || !SLHistoryURL(String(browser->GetMainFrame()->GetURL()))) return;
        NSString *script=SLShieldCosmeticScript(String(browser->GetMainFrame()->GetURL()),String(frame->GetURL()));
        frame->ExecuteJavaScript(script.UTF8String,frame->GetURL(),0);
    }
    void OnFaviconURLChange(CefRefPtr<CefBrowser> source, const std::vector<CefString> &urls) override {
        SLTab *tab_=FindTab(source); if (tab_ && !tab_.rehosting) [owner_ faviconChanged:tab_ urls:urls]; }
    void OnLoadError(CefRefPtr<CefBrowser> source, CefRefPtr<CefFrame> frame, ErrorCode code, const CefString &text, const CefString &url) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) return;
        if (!frame->IsMain() || code == ERR_ABORTED) return;
        tab_.error = [NSString stringWithFormat:@"%@\n%@", String(text), String(url)];
        tab_.loading=NO; [owner_ refresh];
    }
    void OnRenderProcessTerminated(CefRefPtr<CefBrowser> source, TerminationStatus, int, const CefString &) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) return;
        tab_.error=@"This page stopped responding. Reload to try again."; tab_.loading=NO; [owner_ refresh];
    }
    bool OnBeforeBrowse(CefRefPtr<CefBrowser> source, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request, bool, bool) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) return true;
        // Untrusted pages never navigate the browser to local files or OS protocols.
        if (!frame->IsMain()) return false;
        NSString *destination=String(request->GetURL());
        if (tab_.trustedInternal && SLTrustedExtensionURL(destination)) return false;
        return !SLAllowedNavigation(destination);
    }
    bool OnOpenURLFromTab(CefRefPtr<CefBrowser> source, CefRefPtr<CefFrame>, const CefString &url, WindowOpenDisposition, bool gesture) override {
        if (gesture && SLAllowedNavigation(String(url))) [owner_ addTabURL:String(url)];
        return true;
    }
    bool OnBeforePopup(CefRefPtr<CefBrowser> source, CefRefPtr<CefFrame> frame, int popupID, const CefString &url, const CefString &, WindowOpenDisposition, bool gesture, const CefPopupFeatures &, CefWindowInfo &, CefRefPtr<CefClient> &client, CefBrowserSettings &, CefRefPtr<CefDictionaryValue> &, bool *) override {
        SLTab *tab_=FindTab(source);
        if (!tab_ || tab_.rehosting) return true;
        NSString *address=String(url); if (!address.length) address=@"about:blank";
        BOOL extension=SLTrustedExtensionURL(String(frame->GetURL()));
        if (owner_.smokePath.length) fprintf(stderr,"popup requested %s gesture=%d extension=%d\n",address.UTF8String,gesture,extension);
        if (owner_.quitting || (!gesture && !extension) || !(SLAllowedNavigation(address) || (extension && SLTrustedExtensionURL(address)))) return true;
        SLSpace *space=[owner_ spaceForTab:tab_]; if (!space) return true;
        SLTab *popup=[SLTab new]; popup.url=address; popup.title=@"Loading…"; popup.creating=YES; popup.popup=YES; popup.trustedInternal=extension;
        [space.tabs addObject:popup]; popups_[popupID]=popup;
        client=new TabClient(owner_,popup);
        return false;
    }
    void OnBeforePopupAborted(CefRefPtr<CefBrowser> source, int popupID) override {
        auto it=popups_.find(popupID); if (it==popups_.end()) return;
        SLTab *popup=it->second; popups_.erase(it);
        popup.creating=NO; [owner_ tabReadyToClose:popup]; [owner_ tabClosed:popup];
    }
    bool DoClose(CefRefPtr<CefBrowser> source) override {
        SLTab *tab_=FindTab(source);
        if (!tab_ || tab_.rehosting) return false;
        [owner_ closeTools:tab_];
        [owner_ tabReadyToClose:tab_];
        return true; // Destroy only this tab's native view, not the containing window.
    }
    void OnBeforeClose(CefRefPtr<CefBrowser> source) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) { rejected_.erase(source->GetIdentifier()); return; }
        if (owner_.smokePath.length) fprintf(stderr,"closed browser=%d\n",source->GetIdentifier());
        if (tab_.rehosting) {
            [owner_.chromeWindows removeObject:tab_]; tab_->browser=nullptr;
            tabs_.erase(source->GetIdentifier());
            __weak SLController *owner=owner_;
            dispatch_async(dispatch_get_main_queue(),^{ if (owner.quitting) [owner finishQuitIfReady]; else [owner finishSpaceRemoval]; });
            return;
        }
        [owner_ closeTools:tab_];
        tab_->testRegistration=nullptr;
        tab_->browser=nullptr;
        if (!tab_.closing) tab_.closing=YES;
        [owner_ tabReadyToClose:tab_];
        [owner_ tabClosed:tab_];
        tabs_.erase(source->GetIdentifier());
    }
    bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> source, const CefString &, bool reload, CefRefPtr<CefJSDialogCallback> callback) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) return false;
        NSAlert *alert=[NSAlert new];
        alert.messageText=reload ? @"Reload this page?" : @"Leave this page?";
        alert.informativeText=@"Changes you made may not be saved.";
        [alert addButtonWithTitle:@"Stay"]; [alert addButtonWithTitle:reload ? @"Reload" : @"Leave"];
        __weak SLController *owner=owner_; SLTab *tab=tab_;
        [alert beginSheetModalForWindow:owner_.window completionHandler:^(NSModalResponse response) {
            BOOL leave=response==NSAlertSecondButtonReturn;
            if (!leave) [owner closeCancelled:tab];
            callback->Continue(leave, CefString());
        }];
        return true;
    }
    void OnBeforeContextMenu(CefRefPtr<CefBrowser> source, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams>, CefRefPtr<CefMenuModel> menu) override {
        menu->AddSeparator(); menu->AddItem(26501, "Inspect element"); menu->AddItem(26502, "Open Chrome DevTools");
    }
    bool OnContextMenuCommand(CefRefPtr<CefBrowser> source, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams> params, int command, EventFlags) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) return false;
        if (command!=26501 && command!=26502) return false;
        [owner_ showToolsForTab:tab_ point:command==26501 ? CefPoint(params->GetXCoord(),params->GetYCoord()) : CefPoint()];
        return true;
    }
    bool OnBeforeDownload(CefRefPtr<CefBrowser> source, CefRefPtr<CefDownloadItem> item, const CefString &name, CefRefPtr<CefBeforeDownloadCallback> callback) override {
        // Chromium owns CRX validation, permission prompts and installation.
        // Our ordinary Save As panel must not intercept that internal download.
        if (SLExtensionDownload(String(item->GetMimeType()),String(name))) {
            if (owner_.smokePath.length) owner_.smokeExtensionDownloads++;
            return false;
        }
        NSSavePanel *panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=String(name).lastPathComponent;
        [panel beginSheetModalForWindow:owner_.window completionHandler:^(NSModalResponse result) {
            if (result==NSModalResponseOK) callback->Continue(panel.URL.path.UTF8String, false);
        }];
        return true;
    }
    void OnDownloadUpdated(CefRefPtr<CefBrowser> source, CefRefPtr<CefDownloadItem> item, CefRefPtr<CefDownloadItemCallback> callback) override {
        if (SLExtensionDownload(String(item->GetMimeType()),String(item->GetSuggestedFileName()))) {
            if (owner_.smokeExtensionDownloads && [String(item->GetOriginalUrl()) isEqual:[owner_.smokeURL stringByAppendingString:@"extension-package.crx"]]) {
                if (item->IsCanceled() || item->IsInterrupted() || item->IsComplete()) owner_.smokeDownloadSettled=YES;
                else callback->Cancel();
            }
            return;
        }
        if (item->IsComplete()) owner_.status.stringValue=[NSString stringWithFormat:@"Saved %@", String(item->GetFullPath()).lastPathComponent];
        else if (item->IsInProgress()) owner_.status.stringValue=[NSString stringWithFormat:@"Downloading… %d%%", item->GetPercentComplete()];
        else if (item->IsCanceled() || item->IsInterrupted()) owner_.status.stringValue=@"Download stopped";
    }
    void OnFindResult(CefRefPtr<CefBrowser> source, int, int count, const CefRect &, int active, bool) override {
        SLTab *tab_=FindTab(source);
        if (!tab_) return;
        if (owner_.activeTab==tab_) owner_.findCount.stringValue=[NSString stringWithFormat:@"%d of %d", active, count];
    }
private:
    SLTab *FindTab(CefRefPtr<CefBrowser> browser) {
        if (rejected_.count(browser->GetIdentifier())) return nil;
        auto found=tabs_.find(browser->GetIdentifier());
        return found==tabs_.end()?tab_:found->second;
    }
    std::map<int,__strong SLTab *> tabs_;
    std::set<int> rejected_;
    __weak SLController *owner_;
    __strong SLTab *tab_;
    std::map<int,__strong SLTab *> popups_;
    IMPLEMENT_REFCOUNTING(TabClient);
};

CefRefPtr<CefClient> SLDefaultChromeClient() { return new TabClient((SLController *)NSApp.delegate,nil); }

@implementation SLController
- (instancetype)initWithProfile:(NSString *)profile updatesEnabled:(BOOL)updatesEnabled {
    if ((self=[super init])) {
        _updates=[[SLUpdates alloc] initWithEnabled:updatesEnabled];
        _testMode=!updatesEnabled;
        _pendingExternalURLs=[NSMutableArray array];
        _profile=profile; _spaces=[NSMutableArray array]; _closingTabs=[NSMutableArray array]; _closedTabs=[NSMutableArray array];
        _extensionImports=[SLReadExtensionImports([profile stringByAppendingPathComponent:@"extension-imports.json"]) mutableCopy];
        NSDictionary *state=SLReadSession([profile stringByAppendingPathComponent:@"session.json"]);
        _sidebarVisible=[state[@"sidebarVisible"] boolValue];
        _sidebarWidth=SLSidebarWidth(state[@"sidebarWidth"]);
        _sidebarReveal=_sidebarVisible?1:0;
        _toolsPosition=state[@"devToolsPosition"]; _adblockEnabled=[state[@"adblockEnabled"] boolValue];
        _pausedHosts=[state[@"adblockPausedHosts"] mutableCopy];
        SLShieldLoad([NSBundle.mainBundle pathForResource:@"shield-rules" ofType:@"json"]);
        SLShieldConfigure(_adblockEnabled,_pausedHosts);
        for (NSDictionary *raw in state[@"spaces"]) {
            SLSpace *space=[SLSpace new]; space.uid=raw[@"id"]; space.name=raw[@"name"]; space.activeID=raw[@"activeTab"];
            for (NSDictionary *folder in raw[@"folders"]) [space.folders addObject:[folder mutableCopy]];
            for (NSDictionary *entry in raw[@"tabs"]) {
                SLTab *tab=[SLTab new]; tab.uid=entry[@"id"]; tab.title=entry[@"title"]; tab.url=entry[@"url"]; tab.trustedInternal=SLTrustedExtensionURL(tab.url) || SLIsExtensionsPage(tab.url); tab.pinned=[entry[@"pinned"] boolValue];
                tab.pinURL=entry[@"pinURL"]; tab.pinTitle=entry[@"pinTitle"]; tab.folderID=entry[@"folderID"];
                [space.tabs addObject:tab];
            }
            space.history=[[SLHistory alloc] initWithPath:[_profile stringByAppendingPathComponent:[NSString stringWithFormat:@"History/%@.json",space.uid]]];
            for (SLTab *tab in space.tabs) tab.favicon=[[NSImage alloc] initWithContentsOfFile:[self faviconPath:tab.url space:space]];
            [_spaces addObject:space];
            if ([space.uid isEqual:state[@"activeSpace"]]) _activeSpace=space;
        }
        for (SLTab *tab in _activeSpace.tabs) if ([tab.uid isEqual:_activeSpace.activeID]) _activeTab=tab;
    }
    return self;
}
- (NSButton *)button:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    NSButton *button=[NSButton buttonWithImage:Icon(symbol) target:self action:action];
    button.bordered=NO; button.bezelStyle=NSBezelStyleRegularSquare;
    button.imagePosition=NSImageOnly; button.toolTip=label; button.accessibilityLabel=label;
    button.contentTintColor=SLThemeColor(SLSecondaryText);
    return button;
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *label=[NSTextField labelWithString:text];
    label.font=[NSFont systemFontOfSize:size weight:weight]; label.textColor=SLThemeColor(SLText);
    return label;
}
- (void)start {
    _chromeWindows=[NSMutableArray array];
    [NSAppleEventManager.sharedAppleEventManager setEventHandler:self andSelector:@selector(handleOpenURLEvent:reply:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
    _window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1280,820) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
    _window.opaque=NO;
    _window.backgroundColor=NSColor.clearColor;
    _window.title=@"Mica"; _window.titleVisibility=NSWindowTitleHidden; _window.titlebarAppearsTransparent=YES;
    _window.minSize=NSMakeSize(760,500); _window.delegate=self; _window.releasedWhenClosed=NO;
    _window.movableByWindowBackground=YES; [_window center]; if (!NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_TEST_MODE"]) [_window setFrameAutosaveName:@"BrowserWindow"];
    _root=[[SLCanvas alloc] initWithFrame:_window.contentView.bounds]; _root.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    _root.fill=NSColor.clearColor;
    _window.contentView=_root;
    _windowChrome=[[SLWindowChrome alloc] initWithWindow:_window];
    // One material beneath all browser chrome keeps the sidebar, toolbar and
    // viewport margins continuous, including while the sidebar animates.
    _chromeBackground=[[SLChromeMaterial alloc] initWithFrame:_root.bounds];
    _chromeBackground.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; [_root addSubview:_chromeBackground];
    _sidebar=[SLCanvas new]; _sidebar.fill=NSColor.clearColor; [_root addSubview:_sidebar];
    _toolbar=[SLCanvas new]; ((SLCanvas *)_toolbar).fill=NSColor.clearColor; [_root addSubview:_toolbar];
    _viewportBackdrop=[SLViewportBackdrop new]; [_root addSubview:_viewportBackdrop];
    _pageHost=[NSView new]; _pageHost.clipsToBounds=YES; _pageHost.wantsLayer=YES; _pageHost.layer.cornerRadius=8; _pageHost.layer.masksToBounds=YES; [_root addSubview:_pageHost];
    _backButton=[self button:@"chevron.left" label:@"Back (⌘[)" action:@selector(goBack:)];
    _forwardButton=[self button:@"chevron.right" label:@"Forward (⌘])" action:@selector(goForward:)];
    _reloadButton=[self button:@"arrow.clockwise" label:@"Reload (⌘R)" action:@selector(reload:)];
    _toolsButton=[self button:@"curlybraces" label:@"Chrome DevTools (⌥⌘I)" action:@selector(devTools:)];
    _pinButton=[self button:@"pin" label:@"Pin tab (⇧⌘P)" action:@selector(togglePin:)];
    _sidebarButton=[self button:@"sidebar.left" label:@"Toggle sidebar (⌘S)" action:@selector(toggleSidebar:)];
    _shieldButton=[self button:@"shield.lefthalf.filled" label:@"Pause ad blocking for this site" action:@selector(toggleSiteShield:)];
    _extensionsButton=[self button:@"puzzlepiece.extension" label:@"Extensions" action:@selector(showExtensionMenu:)];
    for (NSView *view in @[_backButton,_forwardButton,_reloadButton,_toolsButton,_pinButton,_shieldButton,_extensionsButton]) [_toolbar addSubview:view];
    [_toolbar addSubview:_sidebarButton];
    _navigationOverflow=[self button:@"ellipsis" label:@"Navigation controls" action:@selector(showNavigationMenu:)];
    [_toolbar addSubview:_navigationOverflow];
    _utilityBar=[SLCanvas new]; ((SLCanvas *)_utilityBar).fill=NSColor.clearColor; [_root addSubview:_utilityBar];
    [_utilityBar addSubview:_extensionsButton];
    _sidebarResizeHandle=[SLSidebarResizeHandle new]; _sidebarResizeHandle.toolTip=@"Drag to resize sidebar"; [_root addSubview:_sidebarResizeHandle];
    __weak SLController *resizeOwner=self;
    _sidebarResizeHandle.resizeBy=^(CGFloat delta,BOOL finished) {
        SLController *owner=resizeOwner; if (!owner || !owner.sidebarVisible) return;
        if (!owner.resizingSidebar) {
            owner.resizeStartWidth=owner.sidebarWidth; owner.resizingSidebar=YES;
            [owner hideAddressEditor]; [owner hideExtensionMenu];
        }
        [owner setSidebarWidth:owner.resizeStartWidth+delta];
        if (finished) { owner.resizingSidebar=NO; [owner save]; }
    };
    _toolsButton.hidden=YES; _pinButton.hidden=YES; _shieldButton.hidden=YES;
    _address=[NSTextField new]; _address.bordered=NO; _address.drawsBackground=NO; _address.focusRingType=NSFocusRingTypeNone; _address.font=[NSFont systemFontOfSize:14];
    _address.cell.usesSingleLineMode=YES; _address.cell.scrollable=YES; _address.lineBreakMode=NSLineBreakByTruncatingTail;
    _address.placeholderString=@"Search or enter a URL"; _address.target=self; _address.action=@selector(submitAddress:); _address.delegate=self;
    _address.accessibilityLabel=@"Address";
    _address.textColor=SLThemeColor(SLText);
    _addressPanel=[[SLAddressPanel alloc] initWithAddress:_address target:self];
    _tabList=[SLCanvas new]; _tabList.fill=NSColor.clearColor;
    _tabScroll=[NSScrollView new]; _tabScroll.drawsBackground=NO; _tabScroll.hasVerticalScroller=YES; _tabScroll.autohidesScrollers=YES; _tabScroll.documentView=_tabList;
    _tabScroll.scrollerStyle=NSScrollerStyleOverlay;
    [_sidebar addSubview:_tabScroll];
    _tabScroll.contentView.postsBoundsChangedNotifications=YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sidebarDidScroll:) name:NSViewBoundsDidChangeNotification object:_tabScroll.contentView];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDeactivated:) name:NSApplicationDidResignActiveNotification object:NSApp];
    _spacePicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; _spacePicker.target=self; _spacePicker.action=@selector(changeSpace:); _spacePicker.bordered=NO;
    _spacePicker.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]; _spacePicker.accessibilityLabel=@"Space"; [_sidebar addSubview:_spacePicker];
    _spaceActionsButton=[self button:@"ellipsis" label:@"Space actions" action:@selector(showSpaceMenu:)];
    _spaceActionsButton.identifier=@"spaceActions"; [_sidebar addSubview:_spaceActionsButton];
    _status=[self label:@"" size:11 weight:NSFontWeightRegular]; _status.textColor=NSColor.secondaryLabelColor; _status.lineBreakMode=NSLineBreakByTruncatingMiddle; [_root addSubview:_status];
    _findBar=[SLCanvas new]; _findBar.fill=NSColor.clearColor; [_root addSubview:_findBar];
    _findField=[NSSearchField new]; _findField.placeholderString=@"Find in page"; _findField.target=self; _findField.action=@selector(findNext:); _findField.delegate=self; _findField.accessibilityLabel=@"Find in page"; [_findBar addSubview:_findField];
    // Text changes already search live; only Return should send the action.
    _findField.sendsWholeSearchString=YES;
    _findCount=[self label:@"" size:11 weight:NSFontWeightRegular]; [_findBar addSubview:_findCount];
    NSButton *previous=[self button:@"chevron.up" label:@"Previous match" action:@selector(findPrevious:)]; previous.identifier=@"previous"; [_findBar addSubview:previous];
    NSButton *next=[self button:@"chevron.down" label:@"Next match" action:@selector(findNext:)]; next.identifier=@"next"; [_findBar addSubview:next];
    NSButton *closeFind=[self button:@"xmark" label:@"Close find" action:@selector(closeFind:)]; closeFind.identifier=@"closeFind"; [_findBar addSubview:closeFind];
    _toolsPanel=[SLCanvas new]; [_root addSubview:_toolsPanel];
    [self buildMenus]; [self layout]; [self refresh]; [_window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [_updates start];
    [self ensureContext:_activeSpace]; [self loadTab:_activeTab];
    [self startExtensionImportTimer];
    if (!_activeTab.url.length) [self focusNewTab];
    NSArray *pending=_pendingExternalURLs.copy; [_pendingExternalURLs removeAllObjects]; [self openExternalURLArguments:pending];
    _smokePath=NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_RESULT"];
    _smokeURL=NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_URL"];
    if (_testMode && SLStartUpdateProbe(_profile)) return;
    if (_smokePath.length && _smokeURL.length) {
        _smokeChecks=[NSMutableArray array];
        _smokeTimer=[NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(smokeTick:) userInfo:nil repeats:YES];
    }
}
- (void)layout {
    // AppKit sends resize notifications while the window is still being built.
    if (!_toolsPanel) return;
    CGFloat width=_root.bounds.size.width, height=_root.bounds.size.height, side=round(_sidebarReveal*_sidebarWidth);
    CGFloat buttonY=(SLToolbarHeight-30)/2;
    _sidebar.hidden=side<1; _sidebar.frame=NSMakeRect(side-_sidebarWidth,0,_sidebarWidth,height);
    // The complete group stays beside the traffic lights, with a larger gap
    // between the two groups than between the navigation icons themselves.
    BOOL hiddenSidebar=side<160;
    CGFloat chromeWidth=hiddenSidebar?216:side;
    _toolbar.frame=NSMakeRect(0,0,hiddenSidebar?width:side,SLToolbarHeight);
    BOOL overflow=chromeWidth<216;
    NSArray<NSButton *> *navigation=@[_backButton,_forwardButton,_reloadButton,_sidebarButton];
    CGFloat offset=chromeWidth-117;
    for (NSUInteger i=0;i<navigation.count;i++) {
        navigation[i].hidden=overflow;
        navigation[i].frame=NSMakeRect(offset+i*26,buttonY,24,30);
    }
    _navigationOverflow.hidden=!overflow;
    _navigationOverflow.frame=NSMakeRect(chromeWidth-46,buttonY,28,30);
    _utilityBar.frame=hiddenSidebar?NSMakeRect(MAX(240,width-312),0,MIN(300,width-248),56):NSMakeRect(side-_sidebarWidth+12,height-52,_sidebarWidth-24,36);
    CGFloat utilityWidth=NSWidth(_utilityBar.bounds);
    BOOL label=utilityWidth>=176;
    _extensionsButton.title=label?@"Extensions":@""; _extensionsButton.font=[NSFont systemFontOfSize:13];
    _extensionsButton.imagePosition=label?NSImageLeft:NSImageOnly;
    _extensionsButton.alignment=NSTextAlignmentLeft;
    _extensionsButton.frame=NSMakeRect(4,hiddenSidebar?buttonY:3,label?104:30,30);
    NSUInteger capacity=(NSUInteger)MAX(0,floor((utilityWidth-NSMaxX(_extensionsButton.frame)-8)/32));
    NSUInteger visible=MIN(capacity,_extensionToolbarButtons.count);
    for (NSUInteger i=0;i<_extensionToolbarButtons.count;i++) {
        NSButton *button=_extensionToolbarButtons[i]; button.hidden=i>=visible;
        if (!button.hidden) button.frame=NSMakeRect(utilityWidth-(visible-i)*32,hiddenSidebar?buttonY:3,30,30);
    }
    _sidebarResizeHandle.hidden=_sidebarReveal!=1;
    _sidebarResizeHandle.frame=NSMakeRect(side-8,8,8,MAX(1,height-16));
    _sidebarResizeHandle.sidebarWidth=_sidebarWidth;
    _spacePicker.frame=NSMakeRect(14,58,_sidebarWidth-56,32);
    _spaceActionsButton.frame=NSMakeRect(_sidebarWidth-38,59,26,30);
    _tabScroll.frame=NSMakeRect(12,100,_sidebarWidth-24,MAX(100,height-164));
    [_tabList setFrameSize:NSMakeSize(_tabScroll.contentSize.width,MAX(NSHeight(_tabList.frame),_tabScroll.contentSize.height))];
    _status.frame=NSMakeRect(side+12,height-22,width-side-24,17);
    CGFloat find=_finding?42:0;
    CGFloat top=hiddenSidebar?SLToolbarHeight:8;
    _findBar.hidden=!_finding; _findBar.frame=NSMakeRect(side,top,width-side,42);
    CGFloat findWidth=MAX(120,MIN(240,width-side-210));
    _findField.frame=NSMakeRect(16,7,findWidth,28); _findCount.frame=NSMakeRect(findWidth+24,12,60,18);
    for (NSView *view in _findBar.subviews) {
        if ([view.identifier isEqual:@"previous"]) view.frame=NSMakeRect(findWidth+88,6,28,28);
        if ([view.identifier isEqual:@"next"]) view.frame=NSMakeRect(findWidth+118,6,28,28);
        if ([view.identifier isEqual:@"closeFind"]) view.frame=NSMakeRect(width-side-42,6,28,28);
    }
    CGFloat leftInset=round(8*(1-_sidebarReveal));
    NSRect content=NSMakeRect(side+leftInset,top+find,width-side-leftInset-8,MAX(1,height-top-8-find));
    _viewportBackdrop.frame=NSInsetRect(content,-16,-16); _viewportBackdrop.needsDisplay=YES;
    BOOL docked=_activeTab && (_activeTab->toolsBrowser || _activeTab.toolsCreating) && !_activeTab.windowTools && !_activeTab.toolsClosing;
    NSUInteger pageCorners=15,toolsCorners=0;
    if (docked) {
        if ([_toolsPosition isEqual:@"right"]) { pageCorners=5; toolsCorners=10; }
        else if ([_toolsPosition isEqual:@"left"]) { pageCorners=10; toolsCorners=5; }
        else { pageCorners=3; toolsCorners=12; }
    }
    SLClipViewport(_pageHost,pageCorners); SLClipViewport(_toolsPanel,toolsCorners);
    _toolsPanel.hidden=!docked;
    if (docked) {
        NSRect panel=content;
        if ([_toolsPosition isEqual:@"right"] || [_toolsPosition isEqual:@"left"]) {
            CGFloat split=MAX(320,MIN(520,content.size.width*0.48));
            content.size.width-=split; panel.size.width=split;
            if ([_toolsPosition isEqual:@"left"]) content.origin.x+=split;
            else panel.origin.x+=content.size.width;
        } else {
            CGFloat split=MAX(220,MIN(420,content.size.height*0.48));
            content.size.height-=split; panel.origin.y+=content.size.height; panel.size.height=split;
        }
        _toolsPanel.frame=panel;
        for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) {
            if (tab.windowTools) continue;
            tab.toolsContainer.hidden=tab!=_activeTab;
            tab.toolsContainer.frame=_toolsPanel.bounds;
        }
    }
    _pageHost.frame=content;
    for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) tab.container.frame=_pageHost.bounds;
    _home.frame=_pageHost.bounds;
    NSRect surface=content;
    NSRect screen=[_window convertRectToScreen:[_root convertRect:surface toView:nil]];
    for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab->chrome) {
        bool visible=tab==_activeTab && !tab.error && !tab.closing && tab->browser && !_window.miniaturized;
        tab->chrome->Position(screen,visible,pageCorners);
    }
    [self positionAddressEditor];
    [self positionSuggestions];
    [self positionExtensionMenu];
    [_windowChrome layout];
}
- (void)windowDidUpdate:(NSNotification *)notification { if (notification.object==_window) [_windowChrome layout]; }
- (void)windowWillEnterFullScreen:(NSNotification *)notification { if (notification.object==_window) [_windowChrome beginFullScreenTransition]; }
- (void)windowDidEnterFullScreen:(NSNotification *)notification { if (notification.object==_window) { [_windowChrome endFullScreenTransition]; [self layout]; } }
- (void)windowWillExitFullScreen:(NSNotification *)notification { if (notification.object==_window) [_windowChrome beginFullScreenTransition]; }
- (void)windowDidExitFullScreen:(NSNotification *)notification { if (notification.object==_window) { [_windowChrome endFullScreenTransition]; [self layout]; } }
- (void)windowDidFailToEnterFullScreen:(NSWindow *)window { if (window==_window) { [_windowChrome endFullScreenTransition]; [self layout]; } }
- (void)windowDidFailToExitFullScreen:(NSWindow *)window { if (window==_window) { [_windowChrome endFullScreenTransition]; [self layout]; } }
- (void)windowDidResize:(NSNotification *)notification { [self layout]; }
- (void)windowDidMove:(NSNotification *)notification { [self layout]; }
- (void)windowDidMiniaturize:(NSNotification *)notification { [self hideAddressEditor]; [self hideExtensionMenu]; [self layout]; }
- (void)windowDidDeminiaturize:(NSNotification *)notification { [self layout]; }
- (void)refresh {
    if (!_window || _quitting) return;
    BOOL editing=_address.currentEditor!=nil;
    if (!editing) _address.stringValue=SLDisplayAddress(_activeTab.url);
    _window.title=[NSString stringWithFormat:@"%@ — Mica", _activeTab.title ?: @"New tab"];
    _backButton.enabled=_activeTab && _activeTab->browser && _activeTab->browser->CanGoBack();
    _forwardButton.enabled=_activeTab && _activeTab->browser && _activeTab->browser->CanGoForward();
    _reloadButton.image=Icon(_activeTab.loading?@"xmark":@"arrow.clockwise");
    _pinButton.image=Icon(_activeTab.pinned?@"pin.fill":@"pin");
    _pinButton.enabled=_activeTab.url.length>0;
    _toolsButton.enabled=_activeTab.url.length>0;
    BOOL shield=SLShieldEnabledForURL(_activeTab.url);
    _shieldButton.image=Icon(shield?@"shield.lefthalf.filled":@"shield.slash");
    _shieldButton.contentTintColor=shield?NSColor.controlAccentColor:NSColor.secondaryLabelColor;
    _shieldButton.enabled=_activeTab.url.length>0 && _adblockEnabled;
    _shieldButton.toolTip=!_adblockEnabled?@"Ad blocking is off — enable it in the Privacy menu":(shield?@"Ad blocking on — click to pause for this site":@"Ad blocking paused — click to enable for this site");
    _status.stringValue=_activeTab.error ? @"Page failed to load" : (_activeTab.loading?@"Loading…":@"");
    [_spacePicker removeAllItems];
    for (SLSpace *space in _spaces) { [_spacePicker addItemWithTitle:space.name]; _spacePicker.lastItem.representedObject=space.uid; }
    [_spacePicker selectItemAtIndex:[_spaces indexOfObject:_activeSpace]];
    [self renderSidebar];
    for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) tab.container.hidden=tab!=_activeTab || tab.error!=nil;
    if (!_activeTab.url.length || _activeTab.error || !_activeTab->browser) [self showHome];
    else { [_home removeFromSuperview]; _home=nil; }
    [self layout];
    [_saveTimer invalidate]; _saveTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(save) userInfo:nil repeats:NO];
}
- (NSMenu *)tabMenu:(SLTab *)tab {
    NSMenu *menu=[NSMenu new];
    NSArray *titles=@[tab.pinned?@"Unpin tab":@"Pin tab",@"Duplicate tab",@"Copy address",@"Unload tab",tab.pinned?@"Remove pinned tab":@"Close tab"];
    NSArray *selectors=@[NSStringFromSelector(@selector(pinFromMenu:)),NSStringFromSelector(@selector(duplicateFromMenu:)),NSStringFromSelector(@selector(copyFromMenu:)),NSStringFromSelector(@selector(sleepFromMenu:)),NSStringFromSelector(@selector(closeFromMenu:))];
    for (NSUInteger i=0;i<titles.count;i++) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:titles[i] action:NSSelectorFromString(selectors[i]) keyEquivalent:@""]; item.target=self; item.representedObject=tab.uid; [menu addItem:item];
    }
    [self addFolderMenuTo:menu tab:tab];
    return menu;
}
- (void)showHome {
    NSMutableArray *pins=[NSMutableArray array];
    for (SLTab *tab in _activeSpace.tabs) if (tab.pinned && !tab.closing) {
        [pins addObject:@{@"id":tab.uid,@"title":tab.pinTitle ?: tab.title,@"image":tab.favicon ?: Icon(@"globe")}];
    }
    // Update pins without replacing the field editor or its current query.
    if ([_home isKindOfClass:SLStartPage.class] && [_home.identifier isEqual:_activeTab.uid] && !_activeTab.error) {
        [(SLStartPage *)_home setPinnedItems:pins]; return;
    }
    [_home removeFromSuperview];
    _homeAddress=nil;
    if (!_activeTab.error) {
        SLStartPage *page=[[SLStartPage alloc] initWithFrame:_pageHost.bounds target:self];
        _home=page; page.identifier=_activeTab.uid; _homeAddress=page.address; _homeAddress.delegate=self; [page setPinnedItems:pins];
        [_pageHost addSubview:page]; [page layoutSubtreeIfNeeded]; return;
    }
    SLCanvas *canvas=[[SLCanvas alloc] initWithFrame:_pageHost.bounds]; canvas.fill=NSColor.textBackgroundColor; canvas.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    _home=canvas; [_pageHost addSubview:canvas];
    NSStackView *stack=[NSStackView new]; stack.orientation=NSUserInterfaceLayoutOrientationVertical; stack.alignment=NSLayoutAttributeCenterX; stack.spacing=18; stack.translatesAutoresizingMaskIntoConstraints=NO; [canvas addSubview:stack];
    NSImageView *image=[NSImageView imageViewWithImage:Icon(@"exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")]; image.contentTintColor=NSColor.tertiaryLabelColor;
    [image.widthAnchor constraintEqualToConstant:42].active=YES; [image.heightAnchor constraintEqualToConstant:42].active=YES; [stack addArrangedSubview:image];
    [stack addArrangedSubview:[self label:@"Couldn’t open this page" size:24 weight:NSFontWeightSemibold]];
    NSTextField *description=[self label:_activeTab.error size:13 weight:NSFontWeightRegular];
    description.textColor=NSColor.secondaryLabelColor; description.alignment=NSTextAlignmentCenter; description.maximumNumberOfLines=3; description.lineBreakMode=NSLineBreakByWordWrapping;
    [description.widthAnchor constraintEqualToConstant:440].active=YES; [stack addArrangedSubview:description];
    [stack addArrangedSubview:[NSButton buttonWithTitle:@"Try again" target:self action:@selector(reload:)]];
    [stack.centerXAnchor constraintEqualToAnchor:canvas.centerXAnchor].active=YES;
    [stack.centerYAnchor constraintEqualToAnchor:canvas.centerYAnchor constant:-20].active=YES;
}
- (void)ensureContext:(SLSpace *)space {
    if (!space->context) {
        CefRequestContextSettings settings; settings.persist_session_cookies=true;
        // Chromium profiles must be immediate children of root_cache_path.
        NSString *cachePath=[_profile stringByAppendingPathComponent:[@"Space-" stringByAppendingString:space.uid]];
        [[NSFileManager defaultManager] createDirectoryAtPath:cachePath withIntermediateDirectories:YES attributes:nil error:nil];
        CefString(&settings.cache_path)=cachePath.UTF8String;
        __weak SLController *owner=self; __weak SLSpace *weakSpace=space;
        space->context=CefRequestContext::CreateContext(settings,new ShieldRequests(^{
            dispatch_async(dispatch_get_main_queue(), ^{
                SLSpace *ready=weakSpace; if (!ready || !ready->context) return;
                ready.contextReady=YES;
                ready->context->SetChromeColorScheme(CEF_COLOR_VARIANT_SYSTEM,0);
                if (!owner.quitting && !ready.removing) {
                    ready->extensionSettingsWatch=ready->context->AddPreferenceObserver("extensions.settings",new ExtensionPreferences(owner));
                    ready->extensionPinsWatch=ready->context->AddPreferenceObserver("extensions.pinned_extensions",new ExtensionPreferences(owner));
                }
                if (owner.activeSpace==ready) [owner refreshExtensionToolbar];
                for (SLTab *tab in [ready.tabs copy]) if (tab.creating && !tab->browser) {
                    tab.creating=NO;
                    if (tab.closing || owner.quitting) { [owner tabReadyToClose:tab]; [owner tabClosed:tab]; }
                    else [owner loadTab:tab];
                }
                if ([owner.pendingExtensionMenuSpaceID isEqual:ready.uid]) {
                    owner.pendingExtensionMenuSpaceID=nil;
                    if (owner.activeSpace==ready && !owner.quitting) [owner showExtensionMenu:nil];
                }
            });
        }));
    }
}
- (void)loadTab:(SLTab *)tab {
    if (!tab || tab->browser || tab.creating || !tab.url.length || tab.closing) return;
    SLSpace *space=nil; for (SLSpace *candidate in _spaces) if ([candidate.tabs containsObject:tab]) space=candidate;
    if (!space) return;
    [self ensureContext:space];
    tab.sleeping=NO; tab.error=nil;
    if (!space.contextReady) { tab.creating=YES; tab.loading=YES; return; }
    tab.container=[[NSView alloc] initWithFrame:_pageHost.bounds];
    tab.creating=YES; tab.loading=YES;
    tab->chrome=new ChromeTabHost(self,tab);
    tab->chrome->Create(new TabClient(self,tab),SLBrowserURL(tab.url).UTF8String,space->context);
    [self refresh];
}
- (void)browserCreated:(SLTab *)tab {
    if (!tab->browser) return;
    if (tab.popup && !_quitting) { tab.popup=NO; _activeSpace=[self spaceForTab:tab]; [self selectTab:tab]; }
    if (tab.closing || _quitting) { tab->browser->GetHost()->CloseBrowser(false); return; }
    if (tab==_activeTab && tab->chrome) tab->chrome->Focus();
    if (tab.pendingTools) { tab.pendingTools=NO; [self showToolsForTab:tab point:CefPoint()]; }
    [self refresh];
}
- (void)rehostChromeTab:(SLTab *)tab url:(NSString *)url {
    if (!tab.rehosting || tab.closing || !tab->browser) return;
    SLSpace *target=nil;
    for (SLSpace *space in _spaces) if (space->context && space->context->IsSame(tab->browser->GetHost()->GetRequestContext())) { target=space; break; }
    tab.closing=YES;
    tab->browser->GetHost()->CloseBrowser(true);
    if (_quitting || !target || target.removing) return;
    if ([url isEqual:@"chrome://newtab/"]) url=@"";
    if (url.length && !SLAllowedNavigation(url) && !SLTrustedExtensionURL(url)) return;
    _activeSpace=target; [self addTabURL:url];
}
- (void)navigate:(NSString *)input {
    NSString *url=SLResolveAddress(input);
    if (!url) { NSBeep(); _status.stringValue=@"Enter an http or https address, or a search."; return; }
    [self hideAddressEditor]; [self hideSuggestions];
    if (!url.length) { [self addTabURL:@""]; return; }
    [_window makeFirstResponder:nil];
    if (![_activeTab.url isEqual:url]) { _activeTab.favicon=[[NSImage alloc] initWithContentsOfFile:[self faviconPath:url space:_activeSpace]]; _activeTab.faviconURL=nil; }
    _activeTab.url=url; _activeTab.error=nil; _activeTab.title=SLIsExtensionsPage(url)?@"Extensions":([NSURL URLWithString:url].host ?: url);
    _activeTab.trustedInternal=SLIsExtensionsPage(url) || SLTrustedExtensionURL(url);
    if (_activeTab->browser) _activeTab->browser->GetMainFrame()->LoadURL(SLBrowserURL(url).UTF8String);
    else [self loadTab:_activeTab];
    [self refresh];
}
- (void)addTabURL:(NSString *)url {
    url=SLPublicURL(url ?: @"");
    if (!url.length) for (SLTab *existing in _activeSpace.tabs) if (!existing.url.length && !existing.closing) {
        if (_activeTab!=existing) [self selectTab:existing];
        [self focusNewTab]; return;
    }
    SLTab *tab=[SLTab new]; tab.trustedInternal=SLTrustedExtensionURL(url) || SLIsExtensionsPage(url); tab.url=url;
    if (url.length) tab.title=SLIsExtensionsPage(url)?@"Extensions":([NSURL URLWithString:url].host ?: url);
    [_activeSpace.tabs addObject:tab]; [self selectTab:tab];
    if (!url.length) [self focusNewTab];
}
- (void)selectTab:(SLTab *)tab {
    [self hideAddressEditor];
    [self hideExtensionMenu];
    [self hideSuggestions];
    if (tab.closing) return;
    [self closeFind:nil];
    _activeTab=tab; _activeSpace.activeID=tab.uid;
    for (NSMutableDictionary *folder in _activeSpace.folders) if ([folder[@"id"] isEqual:tab.folderID]) folder[@"collapsed"]=@NO;
    [_window makeFirstResponder:nil]; [self loadTab:tab]; [self refresh];
    if (tab->chrome) tab->chrome->Focus();
}
- (SLTab *)tabWithID:(NSString *)uid { for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if ([tab.uid isEqual:uid]) return tab; return nil; }
- (void)tabClicked:(NSButton *)sender {
    SLTab *tab=[self tabWithID:sender.identifier];
    if (tab==_activeTab && tab) [self focusAddress:sender];
    else if (tab) [self selectTab:tab];
}
- (void)closeTabButton:(NSButton *)sender { SLTab *tab=[self tabWithID:sender.identifier]; [self closeTab:tab sleep:tab.pinned]; }
- (void)newTab:(id)sender { [self addTabURL:@""]; }
- (BOOL)handleChromeCommand:(int)command tab:(SLTab *)tab {
    NSDictionary *actions=@{@"IDC_NEW_TAB":@"newTab:",@"IDC_NEW_WINDOW":@"newTab:",@"IDC_CLOSE_TAB":@"closeActiveTab:",@"IDC_CLOSE_WINDOW":@"closeActiveTab:",@"IDC_RESTORE_TAB":@"reopenTab:",@"IDC_FOCUS_LOCATION":@"focusAddress:",@"IDC_FOCUS_SEARCH":@"focusAddress:",@"IDC_FIND":@"find:",@"IDC_FIND_NEXT":@"findNext:",@"IDC_FIND_PREVIOUS":@"findPrevious:",@"IDC_SELECT_NEXT_TAB":@"nextTab:",@"IDC_SELECT_PREVIOUS_TAB":@"previousTab:",@"IDC_DEV_TOOLS":@"devTools:",@"IDC_DEV_TOOLS_CONSOLE":@"devTools:",@"IDC_DEV_TOOLS_INSPECT":@"devTools:",@"IDC_MANAGE_EXTENSIONS":@"manageChromeExtensions:"};
    for (NSString *name in actions) if (command==cef_id_for_command_id_name(name.UTF8String)) {
        SEL action=NSSelectorFromString(actions[name]); __weak SLController *owner=self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!owner || owner.quitting || tab.closing) return;
            if (owner.activeTab!=tab) { owner.activeSpace=[owner spaceForTab:tab]; [owner selectTab:tab]; }
            [NSApp sendAction:action to:owner from:nil];
        });
        return YES;
    }
    return NO;
}
- (void)submitAddress:(NSTextField *)sender { if (_suggestionPanel.visible) [self acceptSuggestion]; else [self navigate:sender.stringValue]; }
- (void)shortcut:(NSButton *)sender { [self navigate:sender.identifier]; }

- (void)focusNewTab {
    [self hideAddressEditor]; [_window makeKeyAndOrderFront:nil];
    if (!_homeAddress || !_home || _home.hidden) [self showHome];
    [_window makeFirstResponder:_homeAddress]; [_homeAddress selectText:nil];
}
- (void)goBack:(id)sender { if (_activeTab->browser) _activeTab->browser->GoBack(); }
- (void)goForward:(id)sender { if (_activeTab->browser) _activeTab->browser->GoForward(); }
- (void)reload:(id)sender {
    if (!_activeTab.url.length) return;
    _activeTab.error=nil;
    if (_activeTab->browser) { if (_activeTab.loading) _activeTab->browser->StopLoad(); else _activeTab->browser->Reload(); }
    else [self loadTab:_activeTab];
    [self refresh];
}
- (void)hardReload:(id)sender { if (_activeTab->browser) { _activeTab.error=nil; _activeTab->browser->ReloadIgnoreCache(); [self refresh]; } }
- (void)setPinned:(BOOL)pinned tab:(SLTab *)tab {
    if (!tab.url.length) return;
    tab.pinned=pinned; tab.pinURL=pinned?tab.url:nil; tab.pinTitle=pinned?tab.title:nil;
    if (!pinned) tab.folderID=nil;
    [self refresh];
}
- (void)togglePin:(id)sender { [self setPinned:!_activeTab.pinned tab:_activeTab]; }
- (void)pinFromMenu:(NSMenuItem *)sender { SLTab *tab=[self tabWithID:sender.representedObject]; [self setPinned:!tab.pinned tab:tab]; }
- (void)duplicateFromMenu:(NSMenuItem *)sender { [self addTabURL:[self tabWithID:sender.representedObject].url]; }
- (void)copyFromMenu:(NSMenuItem *)sender { [NSPasteboard.generalPasteboard clearContents]; [NSPasteboard.generalPasteboard setString:[self tabWithID:sender.representedObject].url forType:NSPasteboardTypeString]; }
- (void)sleepFromMenu:(NSMenuItem *)sender { [self closeTab:[self tabWithID:sender.representedObject] sleep:YES]; }
- (void)closeFromMenu:(NSMenuItem *)sender { [self closeTab:[self tabWithID:sender.representedObject] sleep:NO]; }
- (void)closeActiveTab:(id)sender {
    for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab.toolsWindow && tab.toolsWindow==NSApp.keyWindow) { [self closeTools:tab]; return; }
    [self closeTab:_activeTab sleep:_activeTab.pinned];
}
- (void)closeTab:(SLTab *)tab sleep:(BOOL)sleep {
    if (!tab || tab.closing) return;
    tab.sleeping=sleep; tab.closing=YES;
    [self closeTools:tab];
    if (tab.creating) return;
    if (tab->browser) { tab->browser->GetHost()->CloseDevTools(); tab->browser->GetHost()->CloseBrowser(false); }
    else { [self tabReadyToClose:tab]; [self tabClosed:tab]; }
}
- (void)tabReadyToClose:(SLTab *)tab {
    if (![_closingTabs containsObject:tab]) [_closingTabs addObject:tab];
    if (!_quitting && !tab.sleeping && ![self spaceForTab:tab].removing) {
        for (SLSpace *space in _spaces) if ([space.tabs containsObject:tab]) {
            if (!tab.importingSettings) { [_closedTabs addObject:@{@"url":tab.url,@"title":tab.title}]; if (_closedTabs.count>20) [_closedTabs removeObjectAtIndex:0]; }
            [space.tabs removeObject:tab]; break;
        }
    }
    // Removing the child NSView lets CEF destroy it without closing our NSWindow.
    for (NSView *view in [tab.container.subviews copy]) [view removeFromSuperview];
    [tab.container removeFromSuperview]; tab.container=nil;
    if (!_quitting && tab==_activeTab) {
        // Saved pins without a live page must stay closed until explicitly opened.
        SLTab *next=nil; for (SLTab *candidate in _activeSpace.tabs) if (candidate!=tab && !candidate.closing && (!candidate.pinned || candidate->browser || candidate.creating)) { next=candidate; break; }
        if (next) [self selectTab:next]; else [self addTabURL:@""];
    }
    [self refresh];
}
- (void)tabClosed:(SLTab *)tab {
    tab.closing=NO; tab.loading=NO;
    if (tab.pinned && tab.sleeping && tab.pinURL.length) {
        tab.url=tab.pinURL; tab.title=tab.pinTitle ?: tab.url; tab.error=nil;
        tab.trustedInternal=SLIsExtensionsPage(tab.url) || SLTrustedExtensionURL(tab.url);
        tab.favicon=[[NSImage alloc] initWithContentsOfFile:[self faviconPath:tab.url space:[self spaceForTab:tab]]]; tab.faviconURL=nil;
    }
    [_closingTabs removeObject:tab];
    if (_quitting) [self finishQuitIfReady];
    else { [self finishSpaceRemoval]; [self refresh]; }
}
- (void)closeCancelled:(SLTab *)tab { tab.closing=NO; tab.sleeping=NO; _quitting=NO; [self startExtensionImportTimer]; [self refresh]; }
- (void)reopenTab:(id)sender { NSDictionary *closed=_closedTabs.lastObject; if (closed) { [_closedTabs removeLastObject]; [self addTabURL:closed[@"url"]]; } }
- (void)toggleSidebar:(id)sender {
    [self hideAddressEditor]; [self hideExtensionMenu];
    _sidebarVisible=!_sidebarVisible; [_sidebarAnimation invalidate]; _sidebarAnimation=nil;
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) { _sidebarReveal=_sidebarVisible?1:0; [self layout]; [self save]; return; }
    _sidebarAnimationFrom=_sidebarReveal; _sidebarAnimationStart=CACurrentMediaTime();
    _sidebarAnimation=[NSTimer scheduledTimerWithTimeInterval:1.0/60 target:self selector:@selector(animateSidebar:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_sidebarAnimation forMode:NSRunLoopCommonModes];
}
- (void)animateSidebar:(NSTimer *)timer {
    CGFloat t=MIN(1,(CACurrentMediaTime()-_sidebarAnimationStart)/0.18), eased=1-pow(1-t,3);
    _sidebarReveal=_sidebarAnimationFrom+((_sidebarVisible?1:0)-_sidebarAnimationFrom)*eased; [self layout];
    if (t>=1) { [_sidebarAnimation invalidate]; _sidebarAnimation=nil; [self save]; }
}
- (void)changeSpace:(id)sender {
    NSString *uid=_spacePicker.selectedItem.representedObject;
    for (SLSpace *space in _spaces) if ([space.uid isEqual:uid]) { [self activateSpace:space]; break; }
}
- (SLSpace *)spaceWithID:(NSString *)uid {
    for (SLSpace *space in _spaces) if ([space.uid isEqual:uid] && !space.removing) return space;
    return nil;
}
- (BOOL)canRemoveSpace:(SLSpace *)space {
    if (!space || space.removing || _quitting) return NO;
    for (SLSpace *other in _spaces) if (other!=space && !other.removing) return YES;
    return NO;
}
- (NSMenu *)spaceMenu {
    NSMenu *menu=[NSMenu new];
    for (NSArray *entry in @[@[@"Rename Space…",@1],@[@"New Folder…",@2]]) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:entry[0] action:@selector(performSpaceAction:) keyEquivalent:@""];
        item.target=self; item.tag=[entry[1] integerValue]; item.representedObject=_activeSpace.uid; [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];
    [self menuItem:@"New Space…" action:@selector(addSpace:) key:@"" flags:0 menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *remove=[[NSMenuItem alloc] initWithTitle:@"Delete Space…" action:@selector(performSpaceAction:) keyEquivalent:@""];
    remove.target=self; remove.tag=3; remove.representedObject=_activeSpace.uid; [menu addItem:remove];
    return menu;
}
- (void)showSpaceMenu:(id)sender {
    [self hideExtensionMenu]; [self hideSuggestions];
    [[self spaceMenu] popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(_spaceActionsButton.frame),NSMaxY(_spaceActionsButton.frame)+2) inView:_sidebar];
}
- (void)performSpaceAction:(NSMenuItem *)sender {
    SLSpace *space=[self spaceWithID:sender.representedObject];
    if (!space || _quitting || ![self validateMenuItem:sender]) return;
    // Keep the menu bound to the space that opened it, even if a page popup
    // changes the active space while the native menu is tracking.
    if (_activeSpace!=space) [self activateSpace:space];
    if (sender.tag==1) [self renameSpace:nil];
    else if (sender.tag==2) [self newFolder:nil];
    else if (sender.tag==3) [self removeSpace:nil];
}
- (void)activateSpace:(SLSpace *)space {
    if (space.removing) return;
    [self hideExtensionMenu];
    if (!space.history) space.history=[[SLHistory alloc] initWithPath:[_profile stringByAppendingPathComponent:[NSString stringWithFormat:@"History/%@.json",space.uid]]];
    _activeSpace=space; SLTab *tab=space.tabs.firstObject;
    [self ensureContext:space]; [self refreshExtensionToolbar];
    for (SLTab *candidate in space.tabs) if ([candidate.uid isEqual:space.activeID]) tab=candidate;
    [self selectTab:tab];
}
- (void)addSpace:(id)sender {
    if (_spaces.count>=24) return;
    NSAlert *alert=[NSAlert new]; alert.messageText=@"Create a space"; alert.informativeText=@"Tabs, pins, and sign-ins stay separate in each space.";
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,280,26)]; field.stringValue=@"New space"; alert.accessoryView=field;
    [alert addButtonWithTitle:@"Create space"]; [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        NSString *name=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (response!=NSAlertFirstButtonReturn || !name.length) return;
        SLSpace *space=[SLSpace new]; space.name=[name substringToIndex:MIN(name.length,48UL)]; SLTab *tab=[SLTab new]; [space.tabs addObject:tab]; space.activeID=tab.uid;
        [self.spaces addObject:space]; [self activateSpace:space]; [self focusAddress:nil];
    }];
    [alert.window makeFirstResponder:field]; [field selectText:nil];
}
- (void)renameSpace:(id)sender {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"Rename space";
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,280,26)]; field.stringValue=_activeSpace.name; alert.accessoryView=field;
    [alert addButtonWithTitle:@"Save"]; [alert addButtonWithTitle:@"Cancel"];
    SLSpace *space=_activeSpace;
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        NSString *name=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (response==NSAlertFirstButtonReturn && name.length) { space.name=[name substringToIndex:MIN(name.length,48UL)]; [self refresh]; }
    }];
}
- (void)removeSpace:(id)sender {
    if (![self canRemoveSpace:_activeSpace]) return;
    SLSpace *space=_activeSpace; NSAlert *alert=[NSAlert new];
    alert.messageText=[NSString stringWithFormat:@"Delete “%@”?",space.name];
    alert.informativeText=@"This closes its tabs and removes the space from Mica. Unsaved page changes will be lost. Its website data, extensions, and a recovery copy of its tabs stay on this Mac.";
    [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Delete Space"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response==NSAlertSecondButtonReturn) [self removeConfirmedSpace:space];
    }];
}
- (void)removeConfirmedSpace:(SLSpace *)space {
    if (!space || space.removing || _quitting) return;
    SLSpace *next=nil; for (SLSpace *candidate in _spaces) if (candidate!=space && !candidate.removing) { next=candidate; break; }
    if (!next) return;
    NSString *path=[_profile stringByAppendingPathComponent:@"removed-spaces.json"];
    NSData *previous=[NSData dataWithContentsOfFile:path]; id raw=previous?[NSJSONSerialization JSONObjectWithData:previous options:NSJSONReadingMutableContainers error:nil]:nil;
    NSMutableArray *archive=[raw isKindOfClass:NSMutableArray.class]?raw:[NSMutableArray array];
    for (NSDictionary *entry in [self snapshot][@"spaces"]) if ([entry[@"id"] isEqual:space.uid]) [archive addObject:entry];
    NSData *data=[NSJSONSerialization dataWithJSONObject:archive options:NSJSONWritingPrettyPrinted error:nil];
    if (![data writeToFile:path options:NSDataWritingAtomic error:nil]) { _status.stringValue=@"Couldn’t save a recovery copy. Space was kept."; return; }
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
    space.removing=YES;
    if (_activeSpace==space) [self activateSpace:next];
    for (SLTab *pending in _chromeWindows.copy) if (pending->browser && space->context && space->context->IsSame(pending->browser->GetHost()->GetRequestContext())) {
        pending.closing=YES; pending->browser->GetHost()->CloseBrowser(true);
    }
    for (SLTab *tab in space.tabs.copy) {
        tab.closing=YES; [self closeTools:tab];
        if (tab->browser) tab->browser->GetHost()->CloseBrowser(true);
        else if (!tab.creating) { [self tabReadyToClose:tab]; [self tabClosed:tab]; }
    }
    [self save]; [self finishSpaceRemoval];
}
- (void)finishSpaceRemoval {
    BOOL changed=NO;
    for (SLSpace *space in _spaces.copy) if (space.removing) {
        BOOL busy=NO;
        for (SLTab *tab in space.tabs) if (tab->browser || tab.creating || tab->toolsBrowser || tab.toolsCreating || (tab->chrome && tab->chrome->HasWindow())) busy=YES;
        for (SLTab *pending in _chromeWindows) if (pending->browser && space->context && space->context->IsSame(pending->browser->GetHost()->GetRequestContext())) busy=YES;
        if (busy) continue;
        space->extensionSettingsWatch=nullptr; space->extensionPinsWatch=nullptr; space->context=nullptr;
        [_spaces removeObject:space]; changed=YES;
    }
    if (changed && !_quitting) { [self save]; [self refresh]; }
}
- (void)nextTab:(id)sender { [self cycleTab:1]; }
- (void)previousTab:(id)sender { [self cycleTab:-1]; }
- (void)cycleTab:(NSInteger)delta { NSInteger count=_activeSpace.tabs.count; if (count) [self selectTab:_activeSpace.tabs[([_activeSpace.tabs indexOfObject:_activeTab]+count+delta)%count]]; }
- (void)numberTab:(NSMenuItem *)sender { NSInteger index=sender.tag==9?_activeSpace.tabs.count-1:sender.tag-1; if (index>=0 && index<(NSInteger)_activeSpace.tabs.count) [self selectTab:_activeSpace.tabs[index]]; }
- (void)devTools:(id)sender { [self showToolsForTab:_activeTab point:CefPoint()]; }
- (void)showToolsForTab:(SLTab *)tab point:(CefPoint)point {
    if (!tab.url.length || !SLAllowedNavigation(tab.url) || tab.closing || _quitting) return;
    [self loadTab:tab]; if (!tab->browser) { tab.pendingTools=YES; return; }
    if (point.x || point.y) { tab.inspectPoint=NSMakePoint(point.x,point.y); tab.inspectPending=YES; }
    if (tab.toolsClosing) { tab.reopenTools=YES; return; }
    if (tab->toolsBrowser || tab.toolsCreating || tab.windowTools) {
        if (tab.toolsWindow) [tab.toolsWindow makeKeyAndOrderFront:nil];
        if (tab.toolsReady && tab.inspectPending) [self inspectInTools:tab];
        return;
    }
    tab.toolsCreating=YES; tab.toolsReady=NO; tab.toolsMessages=0; _devToolsCount++;
    CefBrowserSettings settings;
    CefWindowInfo info;
    if ([_toolsPosition isEqual:@"window"]) {
        tab.windowTools=YES;
        tab.toolsWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1060,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        tab.toolsWindow.title=[@"DevTools — " stringByAppendingString:SLDisplayAddress(tab.url)];
        tab.toolsWindow.minSize=NSMakeSize(500,360); tab.toolsWindow.releasedWhenClosed=NO; tab.toolsWindow.delegate=self;
        [tab.toolsWindow center];
        tab.toolsContainer=[[NSView alloc] initWithFrame:tab.toolsWindow.contentView.bounds];
        tab.toolsContainer.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        [tab.toolsWindow.contentView addSubview:tab.toolsContainer]; [tab.toolsWindow makeKeyAndOrderFront:nil];
    } else {
        tab.toolsContainer=[NSView new]; [_toolsPanel addSubview:tab.toolsContainer];
    }
    tab.toolsContainer.clipsToBounds=YES;
    [self layout];
    info.SetAsChild((__bridge CefWindowHandle)tab.toolsContainer,CefRect(0,0,(int)tab.toolsContainer.bounds.size.width,(int)tab.toolsContainer.bounds.size.height));
    info.runtime_style=CEF_RUNTIME_STYLE_ALLOY;
    auto extra=CefDictionaryValue::Create();
    NSString *script=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"devtools-host" ofType:@"js"] encoding:NSUTF8StringEncoding error:nil];
    NSString *side=tab.windowTools?@"undocked":_toolsPosition;
    script=[NSString stringWithFormat:@"globalThis.__slInitialDockSide='%@';\n%@",side,script];
    extra->SetString("searchlightToolsHost",script.UTF8String);
    if (!CefBrowserHost::CreateBrowser(info,new DockClient(self,tab),"devtools://devtools/bundled/devtools_app.html?can_dock=true",settings,extra,nullptr)) {
        [tab.toolsContainer removeFromSuperview]; tab.toolsContainer=nil; [self toolsClosed:tab];
        _status.stringValue=@"Couldn’t open DevTools. Try Developer → DevTools Position → Window.";
    }
}
- (void)inspectInTools:(SLTab *)tab {
    if (!tab->toolsBrowser || !tab.inspectPending) return;
    tab.inspectPending=NO;
    NSString *script=[NSString stringWithFormat:@"globalThis.__slInspect?.(%d,%d)",(int)tab.inspectPoint.x,(int)tab.inspectPoint.y];
    auto frame=tab->toolsBrowser->GetMainFrame(); frame->ExecuteJavaScript(script.UTF8String,frame->GetURL(),0);
}
- (void)closeActiveTools:(id)sender { [self closeTools:_activeTab]; }
- (void)closeTools:(SLTab *)tab {
    tab.reopenTools=NO;
    if (tab.toolsClosing || (!tab->toolsBrowser && !tab.toolsCreating && !tab.windowTools)) return;
    tab.toolsClosing=YES; if (tab->toolsConnection) tab->toolsConnection->Close(); tab->testRegistration=nullptr;
    if (tab->toolsBrowser) tab->toolsBrowser->GetHost()->CloseBrowser(true);
    [self layout];
}
- (void)toolsClosed:(SLTab *)tab {
    tab.toolsWindow.delegate=nil; [tab.toolsWindow close]; tab.toolsWindow=nil; tab.windowTools=NO;
    _devToolsCount--; tab.toolsClosing=NO; tab.toolsCreating=NO; tab.toolsReady=NO;
    BOOL reopen=tab.reopenTools; tab.reopenTools=NO;
    [self layout];
    if (_quitting) [self finishQuitIfReady];
    else if (reopen && !tab.closing) dispatch_async(dispatch_get_main_queue(), ^{ [self showToolsForTab:tab point:CefPoint()]; });
    if (!_quitting) [self finishSpaceRemoval];
}
- (void)changeToolsPosition:(id)sender {
    NSString *position=[sender representedObject];
    [self applyToolsPosition:position];
}
- (void)syncToolsDockSide:(SLTab *)tab {
    if (!tab->toolsBrowser || !tab.toolsReady || tab.toolsClosing) return;
    NSString *side=[_toolsPosition isEqual:@"window"]?@"undocked":_toolsPosition;
    NSString *script=[NSString stringWithFormat:@"globalThis.__slSetDockSide?.('%@')",side];
    auto frame=tab->toolsBrowser->GetMainFrame(); frame->ExecuteJavaScript(script.UTF8String,frame->GetURL(),0);
}
- (void)applyToolsPosition:(NSString *)position {
    if (![@[@"bottom",@"right",@"left",@"window"] containsObject:position]) return;
    if ([_toolsPosition isEqual:position]) return;
    BOOL windowChange=[_toolsPosition isEqual:@"window"] || [position isEqual:@"window"];
    _toolsPosition=position;
    if (windowChange) for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) {
        if (tab->toolsBrowser || tab.toolsCreating || tab.windowTools) { [self closeTools:tab]; tab.reopenTools=YES; }
    }
    else for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) [self syncToolsDockSide:tab];
    [self layout]; [self save];
}
- (void)toggleSiteShield:(id)sender {
    NSString *host=[NSURLComponents componentsWithString:_activeTab.url].host.lowercaseString;
    if ([host hasSuffix:@"."]) host=[host substringToIndex:host.length-1];
    if (!host.length || !_adblockEnabled) return;
    if ([_pausedHosts containsObject:host]) [_pausedHosts removeObject:host]; else [_pausedHosts addObject:host];
    [self applyShieldSettings];
}
- (void)toggleShield:(id)sender { _adblockEnabled=!_adblockEnabled; [self applyShieldSettings]; }
- (void)applyShieldSettings {
    SLShieldConfigure(_adblockEnabled,_pausedHosts); [self save];
    for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab->browser) {
        std::vector<CefString> frames; tab->browser->GetFrameIdentifiers(frames);
        for (const auto &identifier : frames) {
            auto frame=tab->browser->GetFrameByIdentifier(identifier);
            if (frame) frame->ExecuteJavaScript(SLShieldCosmeticScript(tab.url,String(frame->GetURL())).UTF8String,frame->GetURL(),0);
        }
    }
    // Reload the active page so a paused site can recover blocked resources.
    if (_activeTab->browser) _activeTab->browser->Reload(); [self refresh];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action==@selector(goBack:)) return _backButton.enabled;
    if (item.action==@selector(goForward:)) return _forwardButton.enabled;
    if (item.action==@selector(reload:)) { item.title=_activeTab.loading?@"Stop loading":@"Refresh"; return _activeTab.url.length>0; }
    if (item.action==@selector(makeDefaultBrowser:)) {
        BOOL isDefault=SLIsDefaultBrowser();
        item.title=isDefault?@"Mica Is Your Default Browser":@"Make Mica Default Browser…";
        return !isDefault && !_settingDefaultBrowser && !_quitting;
    }
    if (item.action==@selector(removeSpace:)) return [self canRemoveSpace:_activeSpace];
    if (item.action==@selector(addSpace:)) return !_quitting && _spaces.count<24;
    if (item.action==@selector(performSpaceAction:)) {
        SLSpace *space=[self spaceWithID:item.representedObject];
        if (!space || _quitting) return NO;
        if (item.tag==3) return [self canRemoveSpace:space];
        if (item.tag==2) return space.folders.count<100;
        return item.tag==1;
    }
    if (item.action==@selector(changeToolsPosition:)) item.state=[_toolsPosition isEqual:item.representedObject]?NSControlStateValueOn:NSControlStateValueOff;
    if (item.action==@selector(toggleShield:)) item.state=_adblockEnabled?NSControlStateValueOn:NSControlStateValueOff;
    if (item.action==@selector(toggleSiteShield:)) {
        item.state=SLShieldEnabledForURL(_activeTab.url)?NSControlStateValueOn:NSControlStateValueOff;
        return _adblockEnabled && _activeTab.url.length;
    }
    return YES;
}
- (void)zoomIn:(id)sender { if (_activeTab->browser) { auto host=_activeTab->browser->GetHost(); host->SetZoomLevel(MIN(5,host->GetZoomLevel()+0.5)); } }
- (void)zoomOut:(id)sender { if (_activeTab->browser) { auto host=_activeTab->browser->GetHost(); host->SetZoomLevel(MAX(-5,host->GetZoomLevel()-0.5)); } }
- (void)resetZoom:(id)sender { if (_activeTab->browser) _activeTab->browser->GetHost()->SetZoomLevel(0); }
- (void)find:(id)sender {
    if (!_activeTab || !_activeTab->browser) return;
    [self hideAddressEditor]; [self hideExtensionMenu];
    _finding=YES; [self layout];
    // The Chromium page is a separate key window. Changing the parent's
    // first responder alone leaves subsequent typing in the page.
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_findField]; [_findField selectText:nil];
}
- (BOOL)handleFindShortcut:(NSEvent *)event {
    if (_quitting || !_activeTab || !_activeTab->browser || event.type!=NSEventTypeKeyDown) return NO;
    NSEventModifierFlags modifiers=event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagOption|NSEventModifierFlagControl|NSEventModifierFlagShift);
    if (modifiers!=NSEventModifierFlagCommand || ![event.charactersIgnoringModifiers.lowercaseString isEqual:@"f"]) return NO;
    NSWindow *source=event.window ?: NSApp.keyWindow;
    NSWindow *page=_activeTab->chrome?_activeTab->chrome->NativeWindow():nil;
    // DevTools and extension popups retain their own Find behavior.
    if (source!=_window && source!=page && source!=_addressPanel) return NO;
    NSResponder *focused=source.firstResponder;
    if (source==_window && [focused isKindOfClass:NSView.class] && [(NSView *)focused isDescendantOf:_toolsPanel]) return NO;
    [self find:nil]; return YES;
}
- (void)findNext:(id)sender { if (_activeTab && _activeTab->browser && _findField.stringValue.length) _activeTab->browser->GetHost()->Find(_findField.stringValue.UTF8String,true,false,true); }
- (void)findPrevious:(id)sender { if (_activeTab && _activeTab->browser && _findField.stringValue.length) _activeTab->browser->GetHost()->Find(_findField.stringValue.UTF8String,false,false,true); }
- (void)closeFind:(id)sender {
    if (_activeTab && _activeTab->browser) _activeTab->browser->GetHost()->StopFinding(true);
    [_window makeFirstResponder:nil];
    _finding=NO; _findCount.stringValue=@""; [self layout];
    if (_activeTab && _activeTab->chrome) _activeTab->chrome->Focus();
}
#include "../test/AppearanceSmoke.inc"
#include "../test/AddressSmoke.inc"
#include "../test/SidebarSmoke.inc"
#include "../test/FindSmoke.inc"
#include "DesktopUI.inc"
#include "HistoryUI.inc"
#include "AddressUI.inc"
#include "ExtensionsUI.inc"
#include "ExtensionImportUI.inc"
#include "../test/ExtensionImportSmoke.inc"
#include "SidebarUI.inc"

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object==_address || notification.object==_homeAddress) [self updateSuggestions:notification.object complete:!_suppressCompletion];
    _suppressCompletion=NO;
    if (notification.object==_findField && _activeTab && _activeTab->browser) {
        // CEF restarts when the query changes. Request an active match too;
        // a false final argument only counts matches in the Chrome runtime.
        if (_findField.stringValue.length) _activeTab->browser->GetHost()->Find(_findField.stringValue.UTF8String,true,false,true);
        else { _activeTab->browser->GetHost()->StopFinding(true); _findCount.stringValue=@""; }
    }
}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)view doCommandBySelector:(SEL)command {
    if (control==_findField && (command==@selector(insertNewline:) || command==@selector(insertNewlineIgnoringFieldEditor:))) {
        if (NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift) [self findPrevious:nil];
        else [self findNext:nil];
        return YES;
    }
    if (control==_address || control==_homeAddress) {
        if (command==@selector(deleteBackward:) || command==@selector(deleteForward:)) _suppressCompletion=YES;
        if (command==@selector(moveDown:) || command==@selector(moveUp:)) {
            if (!_suggestionPanel.visible) [self updateSuggestions:(NSTextField *)control complete:NO];
            NSInteger delta=command==@selector(moveDown:)?1:-1;
            _suggestionIndex=(_suggestionIndex+delta+(NSInteger)_suggestions.count)%MAX(1,(NSInteger)_suggestions.count);
            [self renderSuggestions]; return YES;
        }
        if (command==@selector(insertNewline:) && _suggestionPanel.visible) { [self acceptSuggestion]; return YES; }
    }
    if (command==@selector(cancelOperation:)) {
        [self hideAddressEditor];
        [self hideSuggestions];
        if (control==_findField) [self closeFind:nil];
        [_window makeFirstResponder:nil]; _address.stringValue=_activeTab.url;
        if (_activeTab->browser) _activeTab->browser->GetHost()->SetFocus(true);
        return YES;
    }
    return NO;
}
- (NSDictionary *)snapshot {
    NSMutableArray *spaces=[NSMutableArray array];
    for (SLSpace *space in _spaces) {
        NSMutableArray *tabs=[NSMutableArray array];
        if (space.removing) continue;
        for (SLTab *tab in space.tabs) {
            if (tab.importingSettings) continue;
            NSMutableDictionary *entry=[@{@"id":tab.uid,@"url":tab.url,@"title":tab.title,@"pinned":@(tab.pinned)} mutableCopy];
            if (tab.pinned) { entry[@"pinURL"]=tab.pinURL ?: tab.url; entry[@"pinTitle"]=tab.pinTitle ?: tab.title; if (tab.folderID) entry[@"folderID"]=tab.folderID; }
            [tabs addObject:entry];
        }
        [spaces addObject:@{@"id":space.uid,@"name":space.name,@"activeTab":space.activeID ?: @"",@"tabs":tabs,@"folders":space.folders}];
    }
    return @{@"version":@1,@"activeSpace":_activeSpace.uid,@"spaces":spaces,@"sidebarVisible":@(_sidebarVisible),@"sidebarWidth":@(_sidebarWidth),@"adblockEnabled":@(_adblockEnabled),@"adblockPausedHosts":_pausedHosts,@"devToolsPosition":_toolsPosition};
}
- (void)save {
    [_saveTimer invalidate]; _saveTimer=nil;
    NSError *error=nil;
    for (SLSpace *space in _spaces) [space.history save];
    if (!SLWriteSession([self snapshot],[_profile stringByAppendingPathComponent:@"session.json"],&error)) _status.stringValue=@"Couldn’t save this session. Check available disk space.";
}
- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender!=_window) {
        for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab.toolsWindow==sender) { [self closeTools:tab]; return NO; }
        return YES;
    }
    [self requestQuit]; return NO;
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible { [_window makeKeyAndOrderFront:nil]; return YES; }
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }
- (void)requestQuit {
    [_extensionImportTimer invalidate]; _extensionImportTimer=nil;
    if (_extensionImportJob) [self finishExtensionImport:NO];
    [_sidebarAnimation invalidate]; _sidebarAnimation=nil; [self hideAddressEditor]; [self hideExtensionMenu];
    [self hideSuggestions];
    if (_smokePath.length) fprintf(stderr,"smoke: requestQuit at step %ld\n",(long)_smokeStep);
    if (_quitting) return;
    [self save]; _quitting=YES;
    // Dismiss Chrome-owned toolbar bubbles before closing their browser hosts.
    [_window makeKeyAndOrderFront:nil];
    __weak SLController *owner=self;
    dispatch_async(dispatch_get_main_queue(), ^{ [owner closeBrowsersForQuit]; });
}
- (void)closeBrowsersForQuit {
    for (SLTab *window in [_chromeWindows copy]) if (window->browser) window->browser->GetHost()->CloseBrowser(false);
    for (SLSpace *space in _spaces) for (SLTab *tab in [space.tabs copy]) {
        [self closeTools:tab];
        if (tab.creating) tab.closing=YES;
        if (tab->browser) { tab.closing=YES; tab->browser->GetHost()->CloseDevTools(); tab->browser->GetHost()->CloseBrowser(false); }
    }
    [self finishQuitIfReady];
}
- (void)finishQuitIfReady {
    for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab->browser || tab.creating) return;
    if (_closingTabs.count || _devToolsCount || _chromeWindows.count || _chromeCreating) return;
    for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab->chrome && tab->chrome->HasWindow()) return;
    for (SLSpace *space in _spaces) { space->extensionSettingsWatch=nullptr; space->extensionPinsWatch=nullptr; space->context=nullptr; }
    [_window orderOut:nil];
    if (!_quitScheduled) {
        _quitScheduled=YES;
        // Let the final OnBeforeClose callback release its CEF references first.
        CefPostTask(TID_UI,new QuitMessageLoop());
    }
}
- (NSMenuItem *)menuItem:(NSString *)title action:(SEL)action key:(NSString *)key flags:(NSEventModifierFlags)flags menu:(NSMenu *)menu {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key]; item.target=self; item.keyEquivalentModifierMask=flags; [menu addItem:item]; return item;
}
- (void)buildMenus {
    NSMenu *bar=[NSMenu new]; NSApp.mainMenu=bar;
    NSMenu *(^submenu)(NSString *)=^NSMenu *(NSString *title) { NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]; NSMenu *menu=[[NSMenu alloc] initWithTitle:title]; item.submenu=menu; [bar addItem:item]; return menu; };
    NSEventModifierFlags cmd=NSEventModifierFlagCommand, shift=cmd|NSEventModifierFlagShift, alt=cmd|NSEventModifierFlagOption;
    NSMenu *app=submenu(@"Mica");
    NSMenuItem *about=[self menuItem:@"About Mica" action:@selector(orderFrontStandardAboutPanel:) key:@"" flags:0 menu:app]; about.target=NSApp;
    NSMenuItem *updates=[self menuItem:@"Check for Updates…" action:@selector(checkForUpdates:) key:@"" flags:0 menu:app]; updates.target=_updates;
    NSMenuItem *automatic=[self menuItem:@"Automatically Keep Mica Up to Date" action:@selector(toggleAutomaticUpdates:) key:@"" flags:0 menu:app]; automatic.target=_updates;
    [app addItem:NSMenuItem.separatorItem];
    [self menuItem:@"Make Mica Default Browser…" action:@selector(makeDefaultBrowser:) key:@"" flags:0 menu:app];
    [app addItem:NSMenuItem.separatorItem];
    NSMenuItem *hide=[self menuItem:@"Hide Mica" action:@selector(hide:) key:@"h" flags:cmd menu:app]; hide.target=NSApp;
    [app addItem:NSMenuItem.separatorItem]; NSMenuItem *quit=[self menuItem:@"Quit Mica" action:@selector(terminate:) key:@"q" flags:cmd menu:app]; quit.target=NSApp;
    NSMenu *file=submenu(@"File");
    [self menuItem:@"New Tab" action:@selector(newTab:) key:@"t" flags:cmd menu:file];
    [self menuItem:@"Reopen Closed Tab" action:@selector(reopenTab:) key:@"t" flags:shift menu:file];
    [self menuItem:@"Close Tab" action:@selector(closeActiveTab:) key:@"w" flags:cmd menu:file];
    [file addItem:NSMenuItem.separatorItem];
    [self menuItem:@"New Space…" action:@selector(addSpace:) key:@"n" flags:shift menu:file];
    [self menuItem:@"Rename Space…" action:@selector(renameSpace:) key:@"" flags:0 menu:file];
    [self menuItem:@"Delete Space…" action:@selector(removeSpace:) key:@"" flags:0 menu:file];
    [self menuItem:@"New Folder…" action:@selector(newFolder:) key:@"" flags:0 menu:file];
    [self menuItem:@"Pin or Unpin Tab" action:@selector(togglePin:) key:@"p" flags:shift menu:file];
    NSMenu *edit=submenu(@"Edit");
    for (NSArray *item in @[@[@"Undo",@"undo:",@"z"],@[@"Redo",@"redo:",@"Z"],@[@"Cut",@"cut:",@"x"],@[@"Copy",@"copy:",@"c"],@[@"Paste",@"paste:",@"v"],@[@"Select All",@"selectAll:",@"a"]]) {
        NSMenuItem *m=[self menuItem:item[0] action:NSSelectorFromString(item[1]) key:item[2] flags:cmd menu:edit]; m.target=nil;
    }
    [edit addItem:NSMenuItem.separatorItem]; [self menuItem:@"Find in Page" action:@selector(find:) key:@"f" flags:cmd menu:edit];
    [self menuItem:@"Find Next" action:@selector(findNext:) key:@"g" flags:cmd menu:edit];
    [self menuItem:@"Find Previous" action:@selector(findPrevious:) key:@"G" flags:cmd menu:edit];
    NSMenu *view=submenu(@"View");
    [self menuItem:@"Focus Address" action:@selector(focusAddress:) key:@"l" flags:cmd menu:view];
    [self menuItem:@"Toggle Sidebar" action:@selector(toggleSidebar:) key:@"s" flags:cmd menu:view];
    [view addItem:NSMenuItem.separatorItem];
    [self menuItem:@"Reload" action:@selector(reload:) key:@"r" flags:cmd menu:view];
    [self menuItem:@"Reload Without Cache" action:@selector(hardReload:) key:@"r" flags:shift menu:view];
    [self menuItem:@"Back" action:@selector(goBack:) key:@"[" flags:cmd menu:view];
    [self menuItem:@"Forward" action:@selector(goForward:) key:@"]" flags:cmd menu:view];
    [view addItem:NSMenuItem.separatorItem];
    [self menuItem:@"Zoom In" action:@selector(zoomIn:) key:@"=" flags:cmd menu:view];
    [self menuItem:@"Zoom Out" action:@selector(zoomOut:) key:@"-" flags:cmd menu:view];
    [self menuItem:@"Actual Size" action:@selector(resetZoom:) key:@"0" flags:cmd menu:view];
    NSMenu *developer=submenu(@"Developer");
    [self menuItem:@"Open Chrome DevTools" action:@selector(devTools:) key:@"i" flags:alt menu:developer];
    [self menuItem:@"Open Chrome DevTools" action:@selector(devTools:) key:@"j" flags:alt menu:developer];
    NSMenuItem *placement=[self menuItem:@"DevTools Position" action:nil key:@"" flags:0 menu:developer];
    placement.submenu=[NSMenu new];
    for (NSString *position in @[@"bottom",@"right",@"left",@"window"]) {
        NSMenuItem *item=[self menuItem:position.capitalizedString action:@selector(changeToolsPosition:) key:@"" flags:0 menu:placement.submenu]; item.representedObject=position;
    }
    NSMenu *privacy=submenu(@"Privacy");
    [self menuItem:@"Block Ads and Trackers" action:@selector(toggleShield:) key:@"" flags:0 menu:privacy];
    [self menuItem:@"Block Ads on This Site" action:@selector(toggleSiteShield:) key:@"" flags:0 menu:privacy];
    [self menuItem:@"Clear History in This Space" action:@selector(clearHistory:) key:@"" flags:0 menu:privacy];
    NSMenu *extensions=submenu(@"Extensions");
    [self menuItem:@"Manage Extensions…" action:@selector(showExtensions:) key:@"" flags:0 menu:extensions];
    [self menuItem:@"Import from Chrome…" action:@selector(importChromeExtensions:) key:@"" flags:0 menu:extensions];
    [self menuItem:@"Import Progress…" action:@selector(showExtensionImportProgress:) key:@"" flags:0 menu:extensions];
    [self menuItem:@"Get 1Password…" action:@selector(installOnePassword:) key:@"" flags:0 menu:extensions];
    [self menuItem:@"Browse Extensions…" action:@selector(browseExtensions:) key:@"" flags:0 menu:extensions];

    NSMenu *tabs=submenu(@"Tabs");
    [self menuItem:@"Next Tab" action:@selector(nextTab:) key:@"\t" flags:NSEventModifierFlagControl menu:tabs];
    [self menuItem:@"Previous Tab" action:@selector(previousTab:) key:@"\t" flags:NSEventModifierFlagControl|NSEventModifierFlagShift menu:tabs];
    for (NSInteger n=1;n<=9;n++) { NSMenuItem *item=[self menuItem:[NSString stringWithFormat:@"Select Tab %ld",(long)n] action:@selector(numberTab:) key:[NSString stringWithFormat:@"%ld",(long)n] flags:cmd menu:tabs]; item.tag=n; }
    NSMenu *window=submenu(@"Window"); NSApp.windowsMenu=window;
    NSMenuItem *min=[self menuItem:@"Minimize" action:@selector(performMiniaturize:) key:@"m" flags:cmd menu:window]; min.target=nil;
    NSMenuItem *zoom=[self menuItem:@"Zoom" action:@selector(performZoom:) key:@"" flags:0 menu:window]; zoom.target=nil;
}
// Deterministic native/CEF integration test, enabled only by explicit test environment.
- (void)captureView:(NSView *)view filename:(NSString *)filename {
    NSString *base=NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_SCREENSHOT"];
    if (!base.length) return;
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[base.stringByDeletingLastPathComponent stringByAppendingPathComponent:filename] atomically:YES];
}
- (void)extensionProbeTick {
    if ([NSProcessInfo.processInfo.environment[@"MICA_EXTENSION_RESTORE"] isEqual:@"1"]) {
        if (!_activeSpace.contextReady) return;
        NSString *identifier=nil;
        for (NSDictionary *item in [self extensionActions]) if ([item[@"name"] isEqual:@"Mica popup fixture"]) identifier=item[@"id"];
        if (!identifier) return;
        if (![[self pinnedExtensionIDs] containsObject:identifier] || ![[_extensionToolbarButtons valueForKey:@"identifier"] containsObject:identifier]) { [self smokeFinish:@"Pinned extension did not survive restart"]; return; }
        [_smokeChecks addObject:@"Extension pins and toolbar buttons survive a clean restart"];
        [self smokeFinish:nil]; return;
    }
    SLTab *chrome=nil;
    for (SLTab *tab in _activeSpace.tabs) if (tab.trustedInternal && tab->browser) { chrome=tab; break; }
    if (_smokeStep==0) { [self navigate:@"mica://extensions/"]; _smokeStep++; return; }
    if (!chrome || !chrome->browser || chrome->browser->IsLoading()) return;
    if (_smokeStep==1) {
        if (![chrome.url isEqual:@"mica://extensions/"] || ![SLDisplayAddress(chrome.url) isEqual:@"mica://extensions/"]) { [self smokeFinish:@"Extensions manager does not preserve its Mica address"]; return; }
        chrome->browser->GetMainFrame()->ExecuteJavaScript("chrome.developerPrivate.getExtensionsInfo({includeDisabled:true,includeTerminated:true}, e=>{document.title='Extensions:'+JSON.stringify(e.map(x=>({id:x.id,name:x.name,state:x.state})))});", "chrome://extensions/",0);
        _smokeStep++; return;
    }
    if (_smokeStep==2) {
        if (![chrome.title hasPrefix:@"Extensions:"]) return;
        fprintf(stderr,"extension probe: %s\n",chrome.title.UTF8String);
        NSArray *extensions=[NSJSONSerialization JSONObjectWithData:[[chrome.title substringFromIndex:11] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        BOOL enabled=NO;
        for (NSDictionary *entry in extensions) {
            if ([entry[@"id"] isEqual:@"aeblfdkhhhdcdjpifhhbdiojplfjncoa"] && [entry[@"state"] isEqual:@"ENABLED"]) enabled=YES;
            if ([entry[@"name"] isEqual:@"Mica popup fixture"]) _smokePopupExtension=entry[@"id"];
        }
        if (!enabled || !_smokePopupExtension.length) { [self smokeFinish:@"Extension fixtures did not load in the ordinary space profile"]; return; }
        if (_activeSpace->context->HasPreference("extensions.pinned_extensions")) {
            auto pins=CefListValue::Create(); pins->SetString(0,"aeblfdkhhhdcdjpifhhbdiojplfjncoa");
            auto value=CefValue::Create(); value->SetList(pins); CefString error;
            if (!_activeSpace->context->SetPreference("extensions.pinned_extensions",value,error)) { [self smokeFinish:String(error)]; return; }
        }
        [_smokeChecks addObject:@"Official 1Password loads in the ordinary tabs' space profile"];
        [_smokeChecks addObject:@"mica://extensions/ opens the real installed-extension manager in the current space"];
        NSString *script=[NSString stringWithFormat:@"const fixtureID='%@';%s",_smokePopupExtension,R"JS(
          (async()=>{
            const wait=()=>new Promise(r=>setTimeout(r,100));
            function all(root) {
              return [...root.querySelectorAll('*')].flatMap(e=>[e,...(e.shadowRoot?all(e.shadowRoot):[])]);
            }
            async function item(id) {
              for(let i=0;i<100;i++) {
                const found=all(document).find(e=>e.localName==='extensions-item'&&(e.id===id||e.data?.id===id));
                if(found)return found;
                await wait();
              }
              throw Error('Installed extension card not rendered: '+id);
            }
            const info=()=>new Promise(r=>chrome.developerPrivate.getExtensionsInfo({includeDisabled:true},r));
            const onePassword=await item('aeblfdkhhhdcdjpifhhbdiojplfjncoa');
            if(!onePassword.data?.name?.includes('1Password'))throw Error('1Password missing from overview');
            for(const expected of ['DISABLED','ENABLED']) {
              const card=await item(fixtureID);
              const toggle=card.shadowRoot.querySelector('#enableToggle');
              if(!toggle||toggle.disabled)throw Error('Enable control unavailable');
              if(!card.shadowRoot.querySelector('#detailsButton')||!card.shadowRoot.querySelector('#removeButton'))throw Error('Management actions missing');
              toggle.click();
              let changed=false;
              for(let i=0;i<100;i++) {
                if((await info()).find(e=>e.id===fixtureID)?.state===expected){changed=true;break;}
                await wait();
              }
              if(!changed)throw Error('Enable control did not reach '+expected);
              await wait();
            }
            if((await info()).find(e=>e.id==='aeblfdkhhhdcdjpifhhbdiojplfjncoa')?.state!=='ENABLED')throw Error('Unrelated extension changed');
            document.title='Manager controls verified';
          })().catch(e=>document.title='Manager error:'+e.message);
        )JS"];
        chrome->browser->GetMainFrame()->ExecuteJavaScript(script.UTF8String,"chrome://extensions/",0); _smokeStep=30; return;
    }
    if (_smokeStep==30) {
        if ([chrome.title hasPrefix:@"Manager error:"]) { [self smokeFinish:chrome.title]; return; }
        if (![chrome.title isEqual:@"Manager controls verified"]) return;
        [_smokeChecks addObject:@"Installed overview renders 1Password and exposes details/remove; real toggle disables and re-enables fixture"];
        chrome->browser->GetMainFrame()->LoadURL([NSString stringWithFormat:@"chrome-extension://%@/popup.html",_smokePopupExtension].UTF8String); _smokeStep=3; return;
    }
    if (_smokeStep==3) { [self addTabURL:_smokeURL]; _smokeStep++; return; }
    if (_smokeStep==4) {
        BOOL welcomeReady=NO;
        for (SLTab *tab in _activeSpace.tabs) if ([tab.url hasPrefix:@"chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/app/"] && [tab.title containsString:@"1Password"] && !tab.loading && tab->chrome && tab->chrome->HasWindow()) welcomeReady=YES;
        if (!welcomeReady) return; // Vendor setup takes focus; wait before opening a popup.
        if (!_smokePopupPrepared) { [_window makeKeyAndOrderFront:nil]; _smokePopupPrepared=YES; return; }
        SLTab *fixture=nil; for (SLTab *tab in _activeSpace.tabs) if ([tab.url isEqual:_smokeURL]) fixture=tab;
        if (!fixture || !fixture->browser || fixture.loading) return;
        if (_activeTab!=fixture) [self selectTab:fixture];
        if (!fixture->testRegistration) {
            fixture->testRegistration=fixture->browser->GetHost()->AddDevToolsMessageObserver(new ExtensionProbe(self));
            fixture->browser->GetHost()->ExecuteDevToolsMethod(9100,"Runtime.enable",nullptr);
            fixture->browser->GetHost()->ExecuteDevToolsMethod(9101,"Debugger.enable",nullptr);
        }
        if (!_extensionScriptReady || !_extensionScriptLoaded) return;
        [NSApp activateIgnoringOtherApps:YES];
        _activeTab->chrome->Focus();
        if (!NSApp.active || !_activeTab->chrome->IsActive()) return;
        if (!_activeTab->chrome->IsPageOnly()) { [self smokeFinish:@"Ordinary page exposes Chrome's browser interface"]; return; }
        BOOL hasActionIcon=NO;
        for (NSDictionary *item in [self extensionActions]) if ([item[@"id"] isEqual:_smokePopupExtension]) hasActionIcon=item[@"image"]!=nil;
        if (!hasActionIcon) { [self smokeFinish:@"Extension toolbar-only 38px icon did not load"]; return; }
        [self showExtensionMenu:nil];
        NSButton *pin=SLExtensionControl(_extensionPanel.contentView,_smokePopupExtension,@selector(toggleExtensionPin:));
        if (!pin || pin.state!=NSControlStateValueOff) { [self smokeFinish:@"Unpinned extension missing from grid"]; return; }
        [pin performClick:nil];
        if (![[self pinnedExtensionIDs] containsObject:_smokePopupExtension] || ![[_extensionToolbarButtons valueForKey:@"identifier"] containsObject:_smokePopupExtension]) { [self smokeFinish:@"Pin did not add an extension toolbar button"]; return; }
        pin=SLExtensionControl(_extensionPanel.contentView,_smokePopupExtension,@selector(toggleExtensionPin:)); [pin performClick:nil];
        if ([[_extensionToolbarButtons valueForKey:@"identifier"] containsObject:_smokePopupExtension]) { [self smokeFinish:@"Unpin left a toolbar button behind"]; return; }
        pin=SLExtensionControl(_extensionPanel.contentView,_smokePopupExtension,@selector(toggleExtensionPin:)); [pin performClick:nil];
        if (![self smokeWindowChromeAligned]) { [self smokeFinish:@"Pinned extension icon is not aligned or hit-testable"]; return; }
        [self captureView:_extensionPanel.contentView filename:@"extension-grid.png"];
        [self captureView:_root filename:@"extension-toolbar.png"];
        [_smokeChecks addObject:@"Extension grid pin toggles add and remove real toolbar buttons"];
        NSButton *action=SLExtensionControl(_extensionPanel.contentView,_smokePopupExtension,@selector(openExtensionButton:));
        if (!action || !action.image) { [self smokeFinish:@"Extension without shortcut missing from grid"]; return; }
        auto before=_activeSpace->context->GetPreference("extensions.pinned_extensions");
        [action performClick:nil];
        auto after=_activeSpace->context->GetPreference("extensions.pinned_extensions");
        if (!before->IsEqual(after)) { [self smokeFinish:@"Opening an extension changed pinned preferences"]; return; }
        chrome->browser->GetMainFrame()->ExecuteJavaScript("(async()=>{for(let i=0;i<120;i++){await new Promise(r=>setTimeout(r,100));const views=chrome.extension.getViews({type:'popup'});if(views.some(v=>v.document.body?.innerText.includes('Active tab verified:Extension fixture'))){document.title='Popup:Native action opened';return;}}throw Error('Popup document not rendered');})().catch(e=>document.title='Popup error:'+e.message);", "",0);
        _smokeStep=5; return;
    }
    if (_smokeStep==5) {
        if ([chrome.title containsString:@"inactive window"] && _smokeTicks<160) { _smokeStep=4; return; }
        if ([chrome.title hasPrefix:@"Popup error:"]) {
            for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) fprintf(stderr,"probe tab %s %s browser=%d parent=%d\n",tab.title.UTF8String,tab.url.UTF8String,tab->browser?tab->browser->GetIdentifier():-1,tab->chrome && tab->chrome->NativeWindow().parentWindow==_window);
            [self captureView:_activeTab->chrome->NativeWindow().contentView filename:@"chrome-tab.png"];
            [self smokeFinish:chrome.title]; return;
        }
        if (![chrome.title hasPrefix:@"Popup:"]) return;
        if (_chromeWindows.count || _activeTab->chrome->NativeWindow().parentWindow!=_window) { [self smokeFinish:@"Extension escaped the ordinary browser window"]; return; }
        BOOL onboarding=NO;
        for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab->browser) {
            // AppKit removes hidden windows from their parent's child list.
            // Every visible page must be attached; hidden tabs remain hidden.
            if (!tab->chrome || !tab->chrome->IsPageOnly() || !tab->chrome->NativeWindow() || (tab->chrome->NativeWindow().visible && tab->chrome->NativeWindow().parentWindow!=_window)) { [self smokeFinish:[NSString stringWithFormat:@"Extension page does not use Mica's page-only host: %@ (%@)",tab.title,tab.url]]; return; }
            if ([tab.url hasPrefix:@"chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"] && [tab.title containsString:@"1Password"]) onboarding=YES;
        }
        if (!onboarding) { [self smokeFinish:@"1Password welcome page did not open inside Mica"]; return; }
        [_smokeChecks addObject:@"Extension grid opens the real popup without a shortcut and preserves toolbar pins"];
        [_smokeChecks addObject:@"Official 1Password content script executes inside the ordinary localhost tab"];
        [_smokeChecks addObject:@"1Password's signed-out welcome page is attached to the main browser"];
        [_smokeChecks addObject:@"Native extension popup receives activeTab access to the ordinary tab"];
        [_smokeChecks addObject:@"Every page, including extension onboarding, hides Chrome's toolbar and tab strip"];
        [self captureView:_activeTab->chrome->NativeWindow().contentView filename:@"chrome-tab.png"];
        chrome->browser->GetMainFrame()->ExecuteJavaScript("chrome.extension.getViews({type:'popup'}).forEach(view=>view.close());document.title='Popup dismissed';", "",0);
        _smokeStep=6; return;
    }
    if (_smokeStep==6 && [chrome.title isEqual:@"Popup dismissed"]) {
        NSButton *button=nil; for (NSButton *candidate in _extensionToolbarButtons) if ([candidate.identifier isEqual:_smokePopupExtension]) button=candidate;
        if (!button || button.hidden) { [self smokeFinish:@"Pinned extension button unavailable"]; return; }
        [button performClick:nil];
        chrome->browser->GetMainFrame()->ExecuteJavaScript("(async()=>{for(let i=0;i<120;i++){await new Promise(r=>setTimeout(r,100));if(chrome.extension.getViews({type:'popup'}).some(v=>v.document.body?.innerText.includes('Active tab verified:Extension fixture'))){document.title='Toolbar popup verified';return;}}document.title='Toolbar popup error';})()","",0);
        _smokeStep=7; return;
    }
    if (_smokeStep==7) {
        if ([chrome.title isEqual:@"Toolbar popup error"]) { [self smokeFinish:chrome.title]; return; }
        if (![chrome.title isEqual:@"Toolbar popup verified"]) return;
        [_smokeChecks addObject:@"Pinned toolbar icon opens the real extension popup with activeTab permission"];
        chrome->browser->GetMainFrame()->ExecuteJavaScript("chrome.extension.getViews({type:'popup'}).forEach(v=>v.close());document.title='Toolbar popup dismissed'","",0); _smokeStep=8; return;
    }
    if (_smokeStep==8 && [chrome.title isEqual:@"Toolbar popup dismissed"]) [self smokeFinish:nil];
}
- (void)smokeTick:(NSTimer *)timer {
    if (_smokeTicks==0 || _smokeTicks%10==0) fprintf(stderr,"smoke: step %ld, title %s, error %s\n",(long)_smokeStep,_activeTab.title.UTF8String,(_activeTab.error ?: @"none").UTF8String);
    _smokeTicks++;
    if (_smokeTicks>180) { [self smokeFinish:@"Timed out waiting for native/CEF integration"]; return; }
    if (_testMode && [NSProcessInfo.processInfo.environment[@"MICA_FIND_PROBE"] isEqual:@"1"]) { [self findSmokeTick]; return; }
    if (_testMode && [NSProcessInfo.processInfo.environment[@"MICA_IMPORT_PROBE"] isEqual:@"1"]) { [self extensionImportSmokeTick]; return; }
    if ([NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_RESTORE"] isEqual:@"1"]) {
        if ([NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_CHROME_ONLY"] isEqual:@"1"]) {
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            if (_sidebarWidth!=320 || !_sidebarVisible || NSMinX(_pageHost.frame)!=320 || NSMinY(_pageHost.frame)!=8 || _addressPanel.visible) { [self smokeFinish:@"Sidebar width or address-free browsing layout did not survive restart"]; return; }
            [_smokeChecks addObject:@"Resized sidebar width and address-free browsing layout survive a clean restart"];
            [self smokeFinish:nil]; return;
        }
        if (_activeTab.loading || ![_activeTab.title isEqual:@"Cookie present"]) return;
        NSUInteger loaded=0, pins=0;
        for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) { if (tab->browser) loaded++; if (tab.pinned) pins++; }
        if (_spaces.count!=2 || pins!=1 || loaded!=1) { [self smokeFinish:@"Session restoration or lazy loading failed"]; return; }
        for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab.pinned && (space.folders.count!=1 || ![tab.folderID isEqual:space.folders.firstObject[@"id"]] || !tab.pinURL.length)) { [self smokeFinish:@"Pinned folder or saved URL did not survive restart"]; return; }
        [_smokeChecks addObject:@"Saved pin URL and folder membership survive restart without reopening the pin"];
        if (!_adblockEnabled || ![_pausedHosts containsObject:@"example.com"]) { [self smokeFinish:@"Shield preferences were not restored"]; return; }
        if (![_toolsPosition isEqual:@"right"]) { [self smokeFinish:@"DevTools position did not persist"]; return; }
        if (_sidebarWidth!=320 || NSMinX(_pageHost.frame)!=320) { [self smokeFinish:@"Resized sidebar width did not survive restart"]; return; }
        [_smokeChecks addObject:@"Resized sidebar width survives restart"];
        if (!_activeSpace.history.entries.count) { [self smokeFinish:@"History did not persist"]; return; }
        for (SLSpace *space in _spaces) for (SLTab *tab in space.tabs) if (tab.pinned && !tab.favicon) { [self smokeFinish:@"Cached favicon did not restore"]; return; }
        [_smokeChecks addObject:@"Per-space history and cached pin favicons survive restart"];
        [_smokeChecks addObject:@"DevTools position, ad blocking, and per-site preferences persist"];
        [_smokeChecks addObject:@"Spaces, pin, and active tab restored after restart"];
        [_smokeChecks addObject:@"Inactive restored tabs remain unloaded"];
        [_smokeChecks addObject:@"Space cookies persist across a clean restart"];
        [self smokeFinish:nil]; return;
    }
    if ([NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_EXTENSION_PROBE"] isEqual:@"1"]) { [self extensionProbeTick]; return; }
    if (_smokeStep==0 && _smokeAppearanceStage<3) { [self smokeAppearanceTick]; return; }
    switch (_smokeStep) {
        case 0: {
            if (_activeTab->browser) { [self smokeFinish:@"Start page unexpectedly created a Chromium renderer"]; return; }
            NSMenu *spaceMenu=[self spaceMenu]; [spaceMenu update];
            if (_spaces.count!=1 || spaceMenu.itemArray.lastObject.enabled || ![spaceMenu.itemArray.lastObject.title isEqual:@"Delete Space…"] || _spaceActionsButton.action!=@selector(showSpaceMenu:) || !NSContainsRect(_sidebar.bounds,_spaceActionsButton.frame)) { [self smokeFinish:@"Space actions menu is missing or allows deleting the last space"]; return; }
            [_smokeChecks addObject:@"Sidebar space actions expose Delete Space and protect the last space"];
            [_root layoutSubtreeIfNeeded];
            if (!_homeAddress.currentEditor || _homeAddress.hiddenOrHasHiddenAncestor || NSIsEmptyRect(_homeAddress.visibleRect) || !_root.clipsToBounds || !_sidebar.clipsToBounds || !_home.clipsToBounds) {
                [self smokeFinish:@"New browser did not focus a visible search field"]; return;
            }
            _homeAddress.stringValue=@""; [_homeAddress selectText:nil];
            [(NSTextView *)_window.firstResponder insertText:@"localhost:3000" replacementRange:NSMakeRange(NSNotFound,0)];
            if (![_homeAddress.stringValue isEqual:@"localhost:3000"]) { [self smokeFinish:[NSString stringWithFormat:@"Typing after launch failed: %@ (%@)",_homeAddress.stringValue,NSStringFromClass([_window.firstResponder class])]]; return; }
            _homeAddress.stringValue=@"";
            [_smokeChecks addObject:@"Native start page creates no browser view; visible search accepts typing immediately"];
            NSString *blankID=_activeTab.uid; NSUInteger initialCount=_activeSpace.tabs.count;
            [self newTab:nil]; [_root layoutSubtreeIfNeeded];
            [self newTab:nil];
            if (![_activeTab.uid isEqual:blankID] || _activeSpace.tabs.count!=initialCount) { [self smokeFinish:@"Repeated New Tab created duplicate empty tabs"]; return; }
            if (!_homeAddress.currentEditor || NSIsEmptyRect(_homeAddress.visibleRect)) { [self smokeFinish:@"New tab search is not visible and focused"]; return; }
            [(NSTextView *)_window.firstResponder insertText:@"new tab input" replacementRange:NSMakeRange(NSNotFound,0)];
            if (![_homeAddress.stringValue isEqual:@"new tab input"]) { [self smokeFinish:@"Typing in new tab failed"]; return; }
            [self newTab:nil];
            if (![_homeAddress.stringValue isEqual:@"new tab input"] || _activeSpace.tabs.count!=initialCount) { [self smokeFinish:@"Repeated New Tab lost the current query or created another tab"]; return; }
            [_smokeChecks addObject:@"Repeated New Tab reuses the empty tab and preserves its typed query"];
            [self closeActiveTab:nil]; [self focusNewTab];
            _homeAddress.stringValue=@"";
            [_smokeChecks addObject:@"New tab accepts typing without clicking; sidebar and toolbar are clipped to bounds"];
            {
                NSString *path=NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_SCREENSHOT"];
                if (path.length) {
                    NSBitmapImageRep *rep=[_root bitmapImageRepForCachingDisplayInRect:_root.bounds];
                    [_root cacheDisplayInRect:_root.bounds toBitmapImageRep:rep];
                    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
                }
            }
            {
                NSRect original=_window.frame;
                [_window setFrame:NSMakeRect(original.origin.x,original.origin.y,760,500) display:YES];
                [self layout]; [_home layoutSubtreeIfNeeded];
                if (![self smokeWindowChromeAligned]) { [self smokeFinish:@"Window controls lost alignment or hit targets after resizing"]; return; }
                if (!NSContainsRect(_home.bounds,_homeAddress.frame) || !_homeAddress.currentEditor) { [self smokeFinish:@"Start-page input is clipped or unfocused at minimum window size"]; return; }
                for (NSView *view in _home.subviews) if ([view isKindOfClass:NSButton.class] && !NSContainsRect(_home.bounds,view.frame)) { [self smokeFinish:@"Start-page shortcut is clipped at minimum window size"]; return; }
                [self captureView:_root filename:@"native-start-page-small.png"];
                [_window setFrame:original display:YES]; [self layout]; [_home layoutSubtreeIfNeeded];
                [_smokeChecks addObject:@"Start-page search and shortcuts fit the minimum window size"];
            }
            if (![self smokeResizableSidebar]) return;
            [self toggleSidebar:nil]; _smokeStep=40; break;
        }
        case 40:
            if (_sidebarAnimation) return;
            if (_sidebarReveal!=0 || !_sidebar.hidden || NSMinX(_pageHost.frame)!=8 || NSWidth(_root.bounds)-NSMaxX(_pageHost.frame)!=8) { [self smokeFinish:@"Sidebar hide animation ended at an incorrect layout"]; return; }
            if (![self smokeWindowChromeAligned]) { [self smokeFinish:@"Window controls lost alignment after hiding the sidebar"]; return; }
            [self captureView:_root filename:@"native-sidebar-hidden.png"];
            [self toggleSidebar:nil];
            if (_sidebarAnimation) {
                _sidebarAnimationStart-=0.09; [self animateSidebar:_sidebarAnimation];
                CGFloat partial=_sidebarReveal;
                [self toggleSidebar:nil];
                if (partial<=0 || partial>=1 || _sidebarReveal!=partial) { [self smokeFinish:@"Sidebar reversal jumped to an endpoint"]; return; }
                [self toggleSidebar:nil];
            }
            _smokeStep=41; break;
        case 41:
            if (_sidebarAnimation) return;
            if (_sidebarReveal!=1 || _sidebar.hidden || NSMinX(_pageHost.frame)!=216) { [self smokeFinish:@"Sidebar reveal animation ended at an incorrect layout"]; return; }
            [_smokeChecks addObject:@"Sidebar animation reaches both layouts and keeps the viewport aligned"];
            [self navigate:[_smokeURL stringByAppendingString:@"docs/a%20b?query=hello%20world&flag=&repeat=one&repeat=two#section"]]; _smokeStep=46; break;
        case 46:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            if (![self smokeAddressEditing]) return;
            _smokeStep=47; break;
        case 47: {
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            NSString *expected=[_smokeURL stringByAppendingString:@"address-go?retained=yes#fragment"];
            if (![String(_activeTab->browser->GetMainFrame()->GetURL()) isEqual:expected]) { [self smokeFinish:@"Go did not load the edited address in Chromium"]; return; }
            SLTab *tab=_activeTab; NSUInteger count=_activeSpace.tabs.count;
            [self focusAddress:nil]; NSTextView *editor=(NSTextView *)_address.currentEditor;
            NSString *destination=[_smokeURL stringByAppendingString:@"address-return?retained=yes#fragment"];
            [editor insertText:destination replacementRange:NSMakeRange(NSNotFound,0)];
            [editor doCommandBySelector:@selector(insertNewline:)];
            if (_addressPanel.visible || _activeTab!=tab || _activeSpace.tabs.count!=count || ![_activeTab.url isEqual:destination]) { [self smokeFinish:@"Return did not open the edited URL in the same tab"]; return; }
            _smokeStep=48; break;
        }
        case 48:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            if (![String(_activeTab->browser->GetMainFrame()->GetURL()) isEqual:[_smokeURL stringByAppendingString:@"address-return?retained=yes#fragment"]]) { [self smokeFinish:@"Return did not load the edited address in Chromium"]; return; }
            [_smokeChecks addObject:@"Go and Return load edited URLs in the same tab, preserving query and fragment"];
            if ([NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_CHROME_ONLY"] isEqual:@"1"]) { [self setSidebarWidth:320]; [self save]; [self smokeFinish:nil]; return; }
            [self navigate:_smokeURL]; _smokeStep=1; break;
        case 1:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            if (!_activeTab.favicon || !_activeSpace.history.entries.count) return;
            {
                SLTab *original=_activeTab;
                [self newTab:nil]; SLTab *empty=_activeTab;
                NSUInteger count=_activeSpace.tabs.count;
                [self selectTab:original]; [self newTab:nil];
                if (_activeTab!=empty || _activeSpace.tabs.count!=count) { [self smokeFinish:@"New Tab did not return to the existing empty tab"]; return; }
                [_smokeChecks addObject:@"New Tab returns to the existing empty tab from another page"];
                NSTextView *editor=(NSTextView *)_homeAddress.currentEditor;
                [editor insertText:@"127.0.0.1" replacementRange:NSMakeRange(NSNotFound,0)];
                if (!_suggestionPanel.visible || !editor.selectedRange.length || ![_suggestions.firstObject[@"tabID"] isEqual:original.uid]) { [self smokeFinish:@"History inline completion or switch-to-tab suggestion failed"]; return; }
                [self control:_homeAddress textView:editor doCommandBySelector:@selector(moveDown:)];
                if (_suggestionIndex!=1) { [self smokeFinish:@"Suggestion arrow navigation failed"]; return; }
                [self control:_homeAddress textView:editor doCommandBySelector:@selector(moveUp:)];
                [self captureView:_suggestionPanel.contentView filename:@"address-suggestions.png"];
                [self control:_homeAddress textView:editor doCommandBySelector:@selector(insertNewline:)];
                if (_activeTab!=original || _suggestionPanel.visible) { [self smokeFinish:@"Suggestion did not switch to existing tab"]; return; }
                [self closeTab:empty sleep:NO];
                [self focusAddress:nil]; editor=(NSTextView *)_address.currentEditor;
                [editor insertText:@"no matching history" replacementRange:NSMakeRange(NSNotFound,0)];
                if (![_suggestions.lastObject[@"direct"] boolValue]) { [self smokeFinish:@"Search fallback missing"]; return; }
                [self control:_address textView:editor doCommandBySelector:@selector(cancelOperation:)];
                if (_suggestionPanel.visible || _address.currentEditor) { [self smokeFinish:@"Escape failed to dismiss address suggestions"]; return; }
            }
            [_smokeChecks addObject:@"History completes selected suffix, supports arrows/Enter/Escape, switches existing tabs and offers search"];
            [_smokeChecks addObject:@"Page favicon loads through Chromium and appears in native tabs"];
            {
                SLTab *original=_activeTab;
                [self showExtensions:nil]; SLTab *settings=_activeTab;
                if (![settings.url isEqual:@"mica://extensions/"] || !settings.trustedInternal || (!settings.creating && !settings->browser)) { [self smokeFinish:@"Extensions manager routing failed"]; return; }
                [self captureView:_root filename:@"extensions-settings.png"];
                [self selectTab:original]; [self closeTab:settings sleep:NO];
            }
            [_smokeChecks addObject:@"Mica extensions route opens the manager and returns to the active page"];
            [_smokeChecks addObject:@"Localhost navigation and page title"];
            [self togglePin:nil]; [self save];
            if (!_activeTab.pinned) { [self smokeFinish:@"Pin failed"]; return; }
            [_smokeChecks addObject:@"Pin and session persistence"];
            [self captureView:_root filename:@"minimal-browser.png"];
            [self showToolsForTab:_activeTab point:CefPoint(10,10)]; _smokeStep++; break;
        case 2:
            if (!_activeTab.toolsReady || _activeTab.toolsMessages<5) return;
            if (!NSEqualRects(_activeTab.toolsContainer.frame,_toolsPanel.bounds)) { [self smokeFinish:@"Redundant DevTools header still reserves space"]; return; }
            if (_toolsPanel.hidden || NSMinY(_toolsPanel.frame)<NSMaxY(_pageHost.frame) || ![_toolsPosition isEqual:@"bottom"]) { [self smokeFinish:@"DevTools did not dock below the page by default"]; return; }
            [_smokeChecks addObject:@"Bundled Chromium DevTools docks at bottom and exchanges protocol messages"];
            {
                NSString *script=@"(async()=>{const SDK=await import('devtools://devtools/bundled/core/sdk/sdk.js');const target=SDK.TargetManager.TargetManager.instance().primaryPageTarget();if(!target)throw Error('No inspected page target');const UI=await import('devtools://devtools/bundled/ui/legacy/legacy.js');const rect=UI.InspectorView.InspectorView.instance().element.getBoundingClientRect();if(rect.top>2||rect.left>2||rect.width<innerWidth-2||rect.height<innerHeight-2)throw Error('DevTools does not fill its native surface');const result=await target.runtimeAgent().invoke_evaluate({expression:'document.title',returnByValue:true});const dom=await target.domAgent().invoke_getDocument({depth:1});if(result.result.value!=='Searchlight fixture'||!dom.root.children.length)throw Error('Console or DOM inspection failed');document.title='Searchlight DevTools verified';})().catch(e=>console.error('Searchlight test',e))";
                auto frame=_activeTab->toolsBrowser->GetMainFrame(); frame->ExecuteJavaScript(script.UTF8String,frame->GetURL(),0);
            }
            _smokeStep=20; break;
        case 20:
            if (!_activeTab.toolsVerified) return;
            [_smokeChecks addObject:@"DevTools frontend evaluates page JavaScript and reads the inspected DOM"];
            _activeTab->testRegistration=_activeTab->toolsBrowser->GetHost()->AddDevToolsMessageObserver(new ToolsCapture(self));
            _activeTab->toolsBrowser->GetHost()->ExecuteDevToolsMethod(9001,"Page.captureScreenshot",nullptr);
            _smokeStep=21; break;
        case 21:
            if (!_smokeCaptured) return;
            [self applyToolsPosition:@"right"];
            if (NSMinX(_toolsPanel.frame)<NSMaxX(_pageHost.frame) || ![_toolsPosition isEqual:@"right"]) { [self smokeFinish:@"Right dock layout failed"]; return; }
            {
                CACornerMask left=kCALayerMinXMinYCorner|kCALayerMinXMaxYCorner, right=kCALayerMaxXMinYCorner|kCALayerMaxXMaxYCorner;
                NSWindow *page=_activeTab->chrome->NativeWindow();
                if (_pageHost.layer.maskedCorners!=left || _toolsPanel.layer.maskedCorners!=right || page.contentView.layer.maskedCorners!=left || page.styleMask!=NSWindowStyleMaskBorderless ||
                    !NSEqualRects(NSInsetRect(_viewportBackdrop.frame,16,16),NSUnionRect(_pageHost.frame,_toolsPanel.frame))) { [self smokeFinish:@"Docked viewport does not share a square inner seam and one outer shadow"]; return; }
                [_smokeChecks addObject:@"Page and docked DevTools share one outline with square inner corners"];
            }
            _activeTab->toolsBrowser->GetMainFrame()->ExecuteJavaScript("(async()=>{for(let i=0;i<50;i++){if(document.body.classList.contains('right')){document.title='Mica dock:right';return;}await new Promise(r=>setTimeout(r,100));}})()","",0);
            _smokeStep=31; break;
        case 31:
            if (![_activeTab.toolsTestState isEqual:@"Mica dock:right"]) return;
            [_smokeChecks addObject:@"Native placement updates DevTools' built-in dock side"];
            _activeTab->toolsBrowser->GetMainFrame()->ExecuteJavaScript("import('devtools://devtools/bundled/ui/legacy/legacy.js').then(UI=>UI.DockController.DockController.instance().setDockSide('left'))","",0);
            _smokeStep=32; break;
        case 32:
            if (![_toolsPosition isEqual:@"left"]) return;
            if (NSMaxX(_toolsPanel.frame)>NSMinX(_pageHost.frame)) { [self smokeFinish:@"DevTools built-in left dock overlaps page"]; return; }
            _activeTab->toolsBrowser->GetMainFrame()->ExecuteJavaScript("import('devtools://devtools/bundled/ui/legacy/legacy.js').then(UI=>UI.DockController.DockController.instance().setDockSide('bottom'))","",0);
            _smokeStep=33; break;
        case 33:
            if (![_toolsPosition isEqual:@"bottom"]) return;
            if (NSMinY(_toolsPanel.frame)<NSMaxY(_pageHost.frame)) { [self smokeFinish:@"DevTools built-in bottom dock overlaps page"]; return; }
            _activeTab->toolsBrowser->GetMainFrame()->ExecuteJavaScript("import('devtools://devtools/bundled/ui/legacy/legacy.js').then(UI=>UI.DockController.DockController.instance().setDockSide('right'))","",0);
            _smokeStep=34; break;
        case 34:
            if (![_toolsPosition isEqual:@"right"]) return;
            [_smokeChecks addObject:@"DevTools' built-in left, bottom and right controls move the native panel"];
            [self newTab:nil];
            if (!_toolsPanel.hidden) { [self smokeFinish:@"DevTools from another tab remained visible"]; return; }
            [self closeActiveTab:nil];
            if (_toolsPanel.hidden) { [self smokeFinish:@"Returning to a tab did not restore its DevTools"]; return; }
            [_smokeChecks addObject:@"Right dock layout and per-tab visibility"];
            {
                auto frame=_activeTab->toolsBrowser->GetMainFrame();
                frame->ExecuteJavaScript("(async()=>{const SDK=await import('devtools://devtools/bundled/core/sdk/sdk.js');await SDK.TargetManager.TargetManager.instance().primaryPageTarget().debuggerAgent().invoke_pause();document.title='Searchlight paused';})()",frame->GetURL(),0);
            }
            _smokeStep=24; break;
        case 24:
            if (!_activeTab.toolsPausedTest) return;
            _activeTab->toolsBrowser->GetMainFrame()->ExecuteJavaScript("import('devtools://devtools/bundled/ui/legacy/legacy.js').then(UI=>UI.DockController.DockController.instance().setDockSide('undocked'))","",0);
            // This only executes once detaching the old session resumes the page.
            _activeTab.title=@"Waiting for debugger detach";
            _activeTab->browser->GetMainFrame()->ExecuteJavaScript("document.title='Searchlight resumed'",_activeTab.url.UTF8String,0);
            _smokeStep=22; break;
        case 22:
            if (!_activeTab.windowTools || _activeTab.toolsCreating || !_activeTab.toolsReady || !_activeTab.toolsWindow.visible) return;
            if (![_activeTab.title isEqual:@"Searchlight resumed"]) return;
            _activeTab->browser->GetMainFrame()->ExecuteJavaScript("document.title='Searchlight fixture'",_activeTab.url.UTF8String,0);
            [_smokeChecks addObject:@"DevTools' built-in undock opens a window and resumes a paused page on detach"];
            [NSApp activateIgnoringOtherApps:YES];
            [_activeTab.toolsWindow makeKeyAndOrderFront:nil];
            _smokeStep=37; break;
        case 37:
            // App activation is asynchronous. Test the shortcut only once the
            // intended window has keyboard focus, as it would for a real keypress.
            if (NSApp.keyWindow!=_activeTab.toolsWindow) {
                // A Chromium activation callback can arrive after the window
                // is shown. Reacquire test focus before sending the shortcut.
                if (_smokeTicks%10==0) {
                    [NSApp activateIgnoringOtherApps:YES];
                    [_activeTab.toolsWindow makeKeyAndOrderFront:nil];
                }
                return;
            }
            {
                NSEvent *close=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:_activeTab.toolsWindow.windowNumber context:nil characters:@"w" charactersIgnoringModifiers:@"w" isARepeat:NO keyCode:13];
                if (![NSApp.mainMenu performKeyEquivalent:close]) { [self smokeFinish:@"Command-W did not close the DevTools window"]; return; }
            }
            _smokeStep=35; break;
        case 35:
            if (_activeTab.toolsWindow || _devToolsCount) return;
            if (!_activeTab->browser || ![_activeTab.url isEqual:_smokeURL]) { [self smokeFinish:@"Closing DevTools also closed the inspected tab"]; return; }
            [_smokeChecks addObject:@"Command-W in the DevTools window closes only DevTools"];
            [self showToolsForTab:_activeTab point:CefPoint()]; _smokeStep=36; break;
        case 36:
            if (!_activeTab.toolsReady || !_activeTab.toolsWindow.visible) return;
            _activeTab->toolsBrowser->GetMainFrame()->ExecuteJavaScript("import('devtools://devtools/bundled/ui/legacy/legacy.js').then(UI=>UI.DockController.DockController.instance().setDockSide('right'))","",0);
            _smokeStep=23; break;
        case 23:
            if (!_activeTab.toolsReady || !_activeTab->toolsBrowser || _activeTab.windowTools || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            [_smokeChecks addObject:@"DevTools' own window control docks back into Mica and reconnects"];
            [self navigate:[_smokeURL stringByAppendingString:@"second"]]; _smokeStep=3; break;
        case 3:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Second page"]) return;
            if (!_activeTab->browser->CanGoBack()) { [self smokeFinish:@"History missing"]; return; }
            [self goBack:nil]; _smokeStep++; break;
        case 4:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            [_smokeChecks addObject:@"Back navigation"];
            [self find:nil]; _findField.stringValue=@"fixture"; [self findNext:nil];
            [self addTabURL:_smokeURL]; _smokeStep++; break;
        case 5:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            [_smokeChecks addObject:@"Second tab loads"];
            [self closeActiveTab:nil]; _smokeStep++; break;
        case 6: {
            if (_closingTabs.count || _activeSpace.tabs.count!=1) return;
            [_smokeChecks addObject:@"Closing a tab preserves window and pin"];
            NSMutableDictionary *folder=[@{@"id":SLNewID(),@"name":@"Development",@"collapsed":@NO} mutableCopy];
            [_activeSpace.folders addObject:folder];
            NSMenuItem *move=[NSMenuItem new]; move.representedObject=@{@"tab":_activeTab.uid,@"folder":folder[@"id"]}; [self movePinToFolder:move];
            SLTabButton *row=nil; for (NSView *view in _tabList.subviews) if ([view.identifier isEqual:_activeTab.uid]) row=(SLTabButton *)view;
            if (!row || row.iconOnly || row.frame.size.width!=192 || row.indent!=16) { [self smokeFinish:@"Pinned tab is not a full-width folder row"]; return; }
            NSButton *toggle=[NSButton new]; toggle.identifier=folder[@"id"]; [self toggleFolder:toggle];
            for (NSView *view in _tabList.subviews) if ([view.identifier isEqual:_activeTab.uid]) { [self smokeFinish:@"Collapsed folder still shows its pin"]; return; }
            [self toggleFolder:toggle];
            SLTab *parked=[SLTab new]; parked.url=[_smokeURL stringByAppendingString:@"second"]; parked.title=@"Saved pin"; parked.pinned=YES; parked.pinURL=parked.url; parked.pinTitle=parked.title;
            _smokeParkedPin=parked.uid; [_activeSpace.tabs addObject:parked]; [self refresh];
            [_smokeChecks addObject:@"Pins render as named rows and move into collapsible folders"];
            NSEvent *close=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:_window.windowNumber context:nil characters:@"w" charactersIgnoringModifiers:@"w" isARepeat:NO keyCode:13];
            if (![NSApp.mainMenu performKeyEquivalent:close]) { [self smokeFinish:@"Command-W was not handled"]; return; }
            _smokeStep++; break;
        }
        case 7:
            if (_closingTabs.count || _activeTab.url.length) return;
            for (SLTab *tab in _activeSpace.tabs) if (tab.pinned && tab->browser) return;
            if (_devToolsCount) return;
            [_smokeChecks addObject:@"Closing a pin unloads its Chromium view and closes its docked DevTools"];
            for (SLTab *pin in _activeSpace.tabs) if (pin.pinned && ![pin.uid isEqual:_smokeParkedPin] && ![pin.url isEqual:pin.pinURL]) { [self smokeFinish:@"Closed pin did not return to its saved URL"]; return; }
            [_smokeChecks addObject:@"Command-W leaves saved pins closed and focuses the single empty tab"];
            [self closeTab:[self tabWithID:_smokeParkedPin] sleep:NO];
            [self captureView:_root filename:@"native-pins.png"];
            {
                NSButton *shortcut=nil;
                for (NSView *view in _home.subviews) if ([view isKindOfClass:NSButton.class] && [self tabWithID:view.identifier].pinned) shortcut=(NSButton *)view;
                if (!shortcut) { [self smokeFinish:@"Pinned shortcut missing from New Tab"]; return; }
                NSUInteger count=_activeSpace.tabs.count;
                [shortcut performClick:nil];
                if (!_activeTab.pinned || _activeSpace.tabs.count!=count) { [self smokeFinish:@"Pinned shortcut duplicated its tab"]; return; }
            }
            _smokeStep=38; break;
        case 38:
            if (_activeTab.loading || !_activeTab->browser) return;
            [_smokeChecks addObject:@"New Tab shows space pins and opens the existing pinned tab without duplication"];
            [self closeActiveTab:nil]; _smokeStep=39; break;
        case 39:
            if (_closingTabs.count || _activeTab.url.length) return;
            [self navigate:[_smokeURL stringByAppendingString:@"set-cookie"]]; _smokeStep=8; break;
        case 8:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Cookie set"]) return;
            {
                SLSpace *space=[SLSpace new]; space.name=@"Test isolation";
                SLTab *tab=[SLTab new]; tab.url=[_smokeURL stringByAppendingString:@"check-cookie"];
                [space.tabs addObject:tab]; space.activeID=tab.uid;
                [_spaces addObject:space]; [self activateSpace:space];
            }
            _smokeStep++; break;
        case 9:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Cookie absent"]) return;
            for (NSDictionary *entry in _activeSpace.history.entries) if ([entry[@"url"] isEqual:_smokeURL]) { [self smokeFinish:@"History leaked between spaces"]; return; }
            [_smokeChecks addObject:@"History is isolated between spaces"];
            [_smokeChecks addObject:@"New space cannot read the first space’s cookie"];
            [self activateSpace:_spaces.firstObject];
            [self navigate:[_smokeURL stringByAppendingString:@"check-cookie"]]; _smokeStep++; break;
        case 10:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Cookie present"]) return;
            [_smokeChecks addObject:@"Original space retains its sign-in storage"];
            [self navigate:[_smokeURL stringByAppendingString:@"disconnect"]]; _smokeStep++; break;
        case 11:
            if (!_activeTab.error) return;
            [_smokeChecks addObject:@"Network failure shows a recoverable native error page"];
            [self navigate:[_smokeURL stringByAppendingString:@"check-cookie"]]; _smokeStep++; break;
        case 12:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Cookie present"]) return;
            [self navigate:[_smokeURL stringByAppendingString:@"shield"]]; _smokeStep++; break;
        case 13:
            if (![_activeTab.title isEqual:@"Shield blocked hidden safe isolated"]) return;
            [_smokeChecks addObject:@"Ad network request blocked; ad slots hidden; normal content and page isolation preserved"];
            [self toggleSiteShield:nil]; _smokeStep++; break;
        case 14:
            if (![_activeTab.title isEqual:@"Shield allowed visible safe isolated"]) return;
            [_smokeChecks addObject:@"Per-site pause restores network requests and cosmetic content"];
            [self toggleSiteShield:nil]; _smokeStep++; break;
        case 15:
            if (![_activeTab.title isEqual:@"Shield blocked hidden safe isolated"]) return;
            [_smokeChecks addObject:@"Ad blocking resumes for the site"];
            [_pausedHosts addObject:@"example.com"]; SLShieldConfigure(_adblockEnabled,_pausedHosts);
            [self navigate:[_smokeURL stringByAppendingString:@"check-cookie"]]; _smokeStep++; break;
        case 16:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Cookie present"]) return;
            [self showToolsForTab:_activeTab point:CefPoint()]; [self closeTools:_activeTab]; _smokeStep=17; break;
        case 17: {
            if (_devToolsCount) return;
            [_smokeChecks addObject:@"Closing DevTools during creation leaves no orphaned view"];
            if (!_activeTab->chrome || !_activeTab->browser || _activeTab->browser->GetHost()->GetRuntimeStyle()!=CEF_RUNTIME_STYLE_CHROME || _activeTab->chrome->NativeWindow().parentWindow!=_window) { [self smokeFinish:@"Browser is not embedded in the main Mica window"]; return; }
            if (_chromeWindows.count) { [self smokeFinish:@"Unexpected separate Chromium window"]; return; }
            NSRect toolbarScreen=[_window convertRectToScreen:[_toolbar convertRect:_toolbar.bounds toView:nil]];
            if (!_activeTab->chrome->IsPageOnly() || NSIntersectsRect(toolbarScreen,_activeTab->chrome->NativeWindow().frame) || _addressPanel.visible) { [self smokeFinish:@"Navigation replaced Mica's controls with Chrome UI"]; return; }
            [_smokeChecks addObject:@"Pages hide Chrome's toolbar/tab strip and preserve Mica's sidebar controls without a persistent address bar"];
            {
                NSString *downloads=[_profile stringByAppendingPathComponent:@"downloads"];
                [NSFileManager.defaultManager createDirectoryAtPath:downloads withIntermediateDirectories:YES attributes:nil error:nil];
                auto path=CefValue::Create(); path->SetString(downloads.UTF8String); CefString error;
                if (!_activeSpace->context->SetPreference("download.default_directory",path,error)) { [self smokeFinish:String(error)]; return; }
                _activeTab->browser->GetHost()->StartDownload([_smokeURL stringByAppendingString:@"extension-package.crx"].UTF8String);
            }
            _smokeStep=18; break;
        }
        case 18:
            if (!_smokeExtensionDownloads || !_smokeDownloadSettled) return;
            [_smokeChecks addObject:@"Extension packages bypass Mica's Save As panel and use Chromium download handling"];
            {
                SLSpace *temporary=[SLSpace new]; temporary.name=@"Removal fixture"; SLTab *tab=[SLTab new]; tab.url=_smokeURL;
                [temporary.tabs addObject:tab]; temporary.activeID=tab.uid; [_spaces addObject:temporary]; [self activateSpace:temporary]; _smokeStep=42;
            }
            break;
        case 42:
            if (_activeTab.loading || !_activeTab->browser) return;
            _smokeSpaceID=_activeSpace.uid; _smokeSpaceMenu=[self spaceMenu]; [_smokeSpaceMenu update];
            if (!_smokeSpaceMenu.itemArray.lastObject.enabled) { [self smokeFinish:@"Space menu incorrectly disables deletion with multiple spaces"]; return; }
            [_smokeSpaceMenu performActionForItemAtIndex:_smokeSpaceMenu.numberOfItems-1];
            if (!_window.attachedSheet || _spaces.count!=3) { [self smokeFinish:@"Delete Space bypassed its confirmation"]; return; }
            [_window endSheet:_window.attachedSheet returnCode:NSAlertFirstButtonReturn];
            _smokeStep=44; break;
        case 44:
            if (_window.attachedSheet) return;
            if (_spaces.count!=3 || ![self spaceWithID:_smokeSpaceID]) { [self smokeFinish:@"Cancel deleted the space"]; return; }
            [_smokeChecks addObject:@"Cancelling Delete Space keeps its tabs and space intact"];
            [self activateSpace:_spaces.firstObject];
            [_smokeSpaceMenu performActionForItemAtIndex:_smokeSpaceMenu.numberOfItems-1];
            if (!_window.attachedSheet || ![_activeSpace.uid isEqual:_smokeSpaceID]) { [self smokeFinish:@"Space menu targeted a different space after a selection change"]; return; }
            [_window endSheet:_window.attachedSheet returnCode:NSAlertSecondButtonReturn];
            _smokeSpaceMenu=nil; _smokeStep=43; break;
        case 43: {
            if (_spaces.count!=2 || _closingTabs.count) return;
            NSData *archive=[NSData dataWithContentsOfFile:[_profile stringByAppendingPathComponent:@"removed-spaces.json"]];
            NSArray *removed=archive?[NSJSONSerialization JSONObjectWithData:archive options:0 error:nil]:nil;
            if (![removed.lastObject[@"name"] isEqual:@"Removal fixture"] || ![_activeTab.title isEqual:@"Cookie present"]) { [self smokeFinish:@"Space removal lost recovery data or affected the remaining space"]; return; }
            [_smokeChecks addObject:@"Space removal closes its pages, preserves recovery data, and keeps the other spaces intact"];
            [_smokeChecks addObject:@"Delete Space from the sidebar menu confirms and deletes its original target"];
            NSUInteger count=_activeSpace.tabs.count; _smokeExternalOriginalID=_activeTab.uid;
            [self openExternalURLArguments:@[@"javascript:alert(1)",@"file:///etc/passwd",@"chrome://extensions/"]];
            if (_activeSpace.tabs.count!=count) { [self smokeFinish:@"External URL routing accepted a privileged or non-web URL"]; return; }
            NSAppleEventDescriptor *event=[NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass eventID:kAEGetURL targetDescriptor:[NSAppleEventDescriptor descriptorWithProcessIdentifier:NSProcessInfo.processInfo.processIdentifier] returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
            [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:[_smokeURL stringByAppendingString:@"external"]] forKeyword:keyDirectObject];
            NSError *sendError=nil; [event sendEventWithOptions:NSAppleEventSendNoReply timeout:1 error:&sendError];
            if (sendError) { [self smokeFinish:@"Could not dispatch native URL-open event"]; return; }
            _smokeExternalTabCount=count+1;
            _smokeStep=45; break;
        }
        case 45:
            if (_activeTab.loading || ![_activeTab.title isEqual:@"Searchlight fixture"]) return;
            if (_activeSpace.tabs.count!=_smokeExternalTabCount) { [self smokeFinish:@"Native URL-open event did not open a Mica tab"]; return; }
            [self closeActiveTab:nil];
            [self selectTab:[self tabWithID:_smokeExternalOriginalID]];
            [_smokeChecks addObject:@"External web links open in Mica tabs; internal, file and script URLs are rejected"];
            [self setSidebarWidth:320]; [self save]; [self smokeFinish:nil]; break;
    }
}
- (void)smokeFinish:(NSString *)error {
    [_smokeTimer invalidate]; _smokeTimer=nil;
    if (!error) {
        NSString *route=[NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_RESTORE"] isEqual:@"1"]?@"window close":
            ([NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_EXTENSION_PROBE"] isEqual:@"1"]?@"application Quit":@"Command-Q");
        @try {
            fprintf(stderr,"smoke: testing %s with application delegate %s\n",route.UTF8String,NSStringFromClass([NSApp.delegate class]).UTF8String);
            if ([route isEqual:@"window close"]) [_window performClose:nil];
            else if ([route isEqual:@"application Quit"]) [NSApp terminate:nil];
            else {
                [NSApp activateIgnoringOtherApps:YES];
                if (_activeTab->chrome) _activeTab->chrome->Focus(); else [_window makeKeyAndOrderFront:nil];
                NSEvent *quit=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:NSApp.keyWindow.windowNumber context:nil characters:@"q" charactersIgnoringModifiers:@"q" isARepeat:NO keyCode:12];
                [NSApp sendEvent:quit];
            }
            if (!_quitting) error=[route stringByAppendingString:@" did not initiate browser shutdown"];
            else [_smokeChecks addObject:[route stringByAppendingString:@" initiates orderly browser shutdown"]];
        } @catch (NSException *exception) {
            error=[NSString stringWithFormat:@"%@ raised %@: %@",route,exception.name,exception.reason];
        }
    }
    NSDictionary *result=@{@"passed":@(!error),@"error":error ?: @"",@"checks":_smokeChecks ?: @[]};
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:_smokePath atomically:YES];
    [self requestQuit];
}
@end
