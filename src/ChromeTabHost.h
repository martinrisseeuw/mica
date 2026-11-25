#pragma once
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/views/cef_box_layout.h"
#include "include/cef_resource_bundle.h"

// CEF's supported Chrome Views host. The frameless backing window is an
// AppKit child surface confined to the active tab's rectangle; never an
// independent user-facing browser window.
class ChromeTabHost final : public CefWindowDelegate, public CefBrowserViewDelegate {
public:
    ChromeTabHost(SLController *owner, SLTab *tab) : owner_(owner), tab_(tab) {}
    void Create(CefRefPtr<CefClient> client, const CefString &url, CefRefPtr<CefRequestContext> context) {
        CefBrowserSettings settings; settings.background_color=CefColorSetARGB(255,255,255,255);
        view_=CefBrowserView::CreateBrowserView(client,url,settings,nullptr,context,this);
        CefWindow::CreateTopLevelWindow(this);
    }
    cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
    cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
    void OnBrowserCreated(CefRefPtr<CefBrowserView>, CefRefPtr<CefBrowser> browser) override {
        if (tab_) return;
        for (SLSpace *space in owner_.spaces) for (SLTab *tab in space.tabs) {
            if (tab->browser && tab->browser->IsSame(browser)) { tab_=tab; tab->chrome=this; return; }
        }
    }
    CefRefPtr<CefBrowserViewDelegate> GetDelegateForPopupBrowserView(CefRefPtr<CefBrowserView>, const CefBrowserSettings &, CefRefPtr<CefClient>, bool devtools) override {
        return devtools ? nullptr : new ChromeTabHost(owner_,nil);
    }
    bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView>, CefRefPtr<CefBrowserView> popup, bool devtools) override {
        if (devtools) return false;
        auto delegate=popup->GetDelegate();
        auto *host=static_cast<ChromeTabHost *>(static_cast<CefBrowserViewDelegate *>(delegate.get()));
        host->view_=popup;
        CefWindow::CreateTopLevelWindow(host);
        return true;
    }
    ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView>) override { return CEF_CTT_NORMAL; }
    bool IsFrameless(CefRefPtr<CefWindow>) override { return true; }
    bool WithStandardWindowButtons(CefRefPtr<CefWindow>) override { return false; }
    bool CanResize(CefRefPtr<CefWindow>) override { return false; }
    bool CanMinimize(CefRefPtr<CefWindow>) override { return false; }
    bool CanMaximize(CefRefPtr<CefWindow>) override { return false; }
    CefSize GetPreferredSize(CefRefPtr<CefView>) override { return CefSize(1000,700); }
    void OnWindowCreated(CefRefPtr<CefWindow> window) override {
        window_=window;
        CefBoxLayoutSettings layout; layout.horizontal=false;
        auto box=window->SetToBoxLayout(layout);
        window->AddChildView(view_);
        toolbar_=view_->GetChromeToolbar();
        // Keep Chromium's extension action infrastructure, but never show its
        // browser controls. The native Mica menu dispatches registered actions.
        if (toolbar_) { window->AddChildViewAt(toolbar_,0); toolbar_->SetVisible(false); }
        box->SetFlexForView(view_,1);
        NSWindow *native=NativeWindow();
        // A page surface is not an independent macOS window. Remove system
        // window rounding; Mica clips only the viewport's exposed corners.
        native.styleMask=NSWindowStyleMaskBorderless;
        native.opaque=NO; native.backgroundColor=NSColor.clearColor;
        native.hasShadow=NO; native.movable=NO; native.appearance=nil;
        native.collectionBehavior=NSWindowCollectionBehaviorFullScreenAuxiliary;
        [owner_.window addChildWindow:native ordered:NSWindowAbove];
        [native orderOut:nil];
    }
    void OnWindowDestroyed(CefRefPtr<CefWindow>) override {
        NSWindow *native=NativeWindow();
        [native.parentWindow removeChildWindow:native];
        window_=nullptr; toolbar_=nullptr; view_=nullptr;
        __weak SLController *owner=owner_;
        dispatch_async(dispatch_get_main_queue(), ^{ if (owner.quitting) [owner finishQuitIfReady]; else [owner finishSpaceRemoval]; });
    }
    bool CanClose(CefRefPtr<CefWindow>) override {
        auto browser=view_?view_->GetBrowser():nullptr;
        return !browser || browser->GetHost()->TryCloseBrowser();
    }
    void OnWindowActivationChanged(CefRefPtr<CefWindow>, bool active) override {
        if (active && tab_ && owner_.activeTab!=tab_ && !tab_.closing && !owner_.quitting) {
            __weak SLController *owner=owner_; __weak SLTab *tab=tab_;
            dispatch_async(dispatch_get_main_queue(), ^{ if (tab && !tab.closing) [owner selectTab:tab]; });
        }
    }
    bool IsPageOnly() const { return window_ && view_ && toolbar_ && !toolbar_->IsVisible() && view_->GetBounds().y==0; }
    bool TriggerExtensionAction(CefRefPtr<CefRequestContext> context, NSString *identifier, NSArray<NSString *> *labels) {
        if (!window_ || !toolbar_ || !view_ || !context) return false;
        auto saved=context->GetPreference("extensions.pinned_extensions");
        if (!saved || saved->GetType()!=VTYPE_LIST) return false;
        auto pins=CefListValue::Create(); pins->SetString(0,identifier.UTF8String);
        auto temporary=CefValue::Create(); temporary->SetList(pins); CefString error;
        if (!context->SetPreference("extensions.pinned_extensions",temporary,error)) return false;
        Focus(); toolbar_->SetVisible(true); window_->Layout();
        NSString *label=String(CefResourceBundle::GetGlobal()->GetLocalizedString(
            cef_id_for_pack_string_name("IDS_TOOLTIP_EXTENSIONS_BUTTON")));
        id menuButton=nil, action=nil;
        NSMutableArray *queue=[NSMutableArray arrayWithObject:NativeWindow().contentView];
        NSMutableSet *seen=[NSMutableSet set];
        while (queue.count && seen.count<512) {
            id element=queue.firstObject; [queue removeObjectAtIndex:0];
            if ([seen containsObject:element]) continue; [seen addObject:element];
            if ([element respondsToSelector:@selector(accessibilityRole)] &&
                [[element accessibilityRole] isEqual:NSAccessibilityPopUpButtonRole] &&
                [[[element accessibilityLabel] componentsSeparatedByString:@"\n"].firstObject isEqual:label]) menuButton=element;
            if ([element respondsToSelector:@selector(accessibilityChildren)])
                [queue addObjectsFromArray:[element accessibilityChildren] ?: @[]];
        }
        // The temporary pin selects exactly one real Chromium action. Resolve
        // its sibling before the menu button. Require one matching accessible
        // title; ambiguous names fail rather than opening another extension.
        if (menuButton) {
            NSArray *siblings=[[menuButton accessibilityParent] accessibilityChildren];
            for (id sibling in siblings) {
                if (sibling==menuButton) break;
                if ([sibling respondsToSelector:@selector(accessibilityRole)] && [[sibling accessibilityRole] isEqual:NSAccessibilityPopUpButtonRole] && [labels containsObject:[[sibling accessibilityLabel] componentsSeparatedByString:@"\n"].firstObject ?: @""]) {
                    if (action) { action=nil; break; }
                    action=sibling;
                }
            }
        }
        toolbar_->SetVisible(false); window_->Layout();
        // Restore the user's pin preference in the same UI turn, before the
        // action runs. Chromium still owns the popup and activeTab permission.
        bool restored=context->SetPreference("extensions.pinned_extensions",saved,error);
        if (owner_.smokePath.length) fprintf(stderr,"extension action found=%d restored=%d\n",action!=nil,restored);
        return restored && action && [action accessibilityPerformPress];
    }
    void Position(NSRect screenFrame, bool visible, NSUInteger corners=15) {
        if (!window_) return;
        NSWindow *native=NativeWindow();
        SLClipViewport(native.contentView,corners);
        if (!NSIsEmptyRect(screenFrame) && !NSEqualRects(native.frame,screenFrame)) [native setFrame:screenFrame display:YES];
        window_->Layout();
        if (visible && !window_->IsVisible()) window_->Show();
        else if (!visible && window_->IsVisible()) window_->Hide();
        if (visible && native.parentWindow!=owner_.window) [owner_.window addChildWindow:native ordered:NSWindowAbove];
    }
    void Focus() { if (window_ && view_) { window_->Activate(); [NativeWindow() makeKeyAndOrderFront:nil]; view_->RequestFocus(); } }
    bool HasWindow() const { return window_!=nullptr; }
    bool IsActive() const { return window_ && window_->IsActive(); }
    NSWindow *NativeWindow() const {
        if (!window_) return nil;
        NSView *native=(__bridge NSView *)window_->GetWindowHandle();
        return native.window;
    }
private:
    __weak SLController *owner_;
    __weak SLTab *tab_;
    CefRefPtr<CefWindow> window_;
    CefRefPtr<CefBrowserView> view_;
    CefRefPtr<CefView> toolbar_;
    IMPLEMENT_REFCOUNTING(ChromeTabHost);
};
