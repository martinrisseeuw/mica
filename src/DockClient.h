#pragma once
#include "include/cef_devtools_message_observer.h"

// This bridge belongs to one trusted DevTools frontend and one inspected tab.
// Normal page clients never expose these IPC handlers.
class DockClient final : public CefClient, public CefLifeSpanHandler,
    public CefRequestHandler, public CefDisplayHandler, public CefLoadHandler {
public:
    DockClient(SLController *owner, SLTab *tab) : owner_(owner), tab_(tab) {}
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        tab_->toolsBrowser=browser; tab_.toolsCreating=NO;
        if (tab_->browser && !tab_.toolsClosing) {
            tab_->toolsConnection=new ToolsConnection(owner_,tab_,browser);
            tab_->toolsConnection->Start();
        }
        NSView *view=(__bridge NSView *)browser->GetHost()->GetWindowHandle();
        view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        if (tab_.toolsClosing || tab_.closing || owner_.quitting) browser->GetHost()->CloseBrowser(true);
        [owner_ layout];
    }
    bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request, bool, bool) override {
        const std::string url=request->GetURL();
        return frame->IsMain() && url.rfind("devtools://devtools/bundled/devtools_app.html",0)!=0;
    }
    bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int, const CefString &, const CefString &, WindowOpenDisposition, bool, const CefPopupFeatures &, CefWindowInfo &, CefRefPtr<CefClient> &, CefBrowserSettings &, CefRefPtr<CefDictionaryValue> &, bool *) override { return true; }
    void OnTitleChange(CefRefPtr<CefBrowser>, const CefString &title) override {
        if (owner_.smokePath.length && title=="Searchlight DevTools verified") tab_.toolsVerified=YES;
        if (owner_.smokePath.length && title=="Searchlight paused") tab_.toolsPausedTest=YES;
        if (owner_.smokePath.length && [String(title) hasPrefix:@"Mica dock:"]) tab_.toolsTestState=String(title);
    }
    void OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, ErrorCode code, const CefString &message, const CefString &url) override {
        if (owner_.smokePath.length) fprintf(stderr,"tools load error: %d %s %s\n",code,message.ToString().c_str(),url.ToString().c_str());
    }
    bool OnConsoleMessage(CefRefPtr<CefBrowser>, cef_log_severity_t level, const CefString &message, const CefString &, int) override {
        // The web-host fallbacks are intentional; other frontend errors stay visible.
        if (message.ToString().rfind("Incompatible embedder: method Host.InspectorFrontendHost.",0)==0) return true;
        if (owner_.smokePath.length && level>=LOGSEVERITY_WARNING) fprintf(stderr,"tools: %s\n",message.ToString().c_str());
        return false;
    }
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefProcessId source, CefRefPtr<CefProcessMessage> message) override {
        if (source!=PID_RENDERER || message->GetName()!="Searchlight.Tools" || !tab_->toolsBrowser || !browser->IsSame(tab_->toolsBrowser) || !frame->IsMain() || tab_.toolsClosing) return false;
        NSString *url=String(frame->GetURL());
        if (![url isEqual:@"devtools://devtools/bundled/devtools_app.html"] && ![url hasPrefix:@"devtools://devtools/bundled/devtools_app.html?"]) return false;
        auto value=CefParseJSON(message->GetArgumentList()->GetString(0),JSON_PARSER_RFC);
        if (!value || value->GetType()!=VTYPE_DICTIONARY) return true;
        auto data=value->GetDictionary(); std::string kind=data->GetString("kind");
        if (kind=="protocol" && tab_->browser) {
            std::string protocol=data->GetString("value");
            if (protocol.size()<16*1024*1024 && tab_->toolsConnection) tab_->toolsConnection->Send(protocol);
        } else if (kind=="ready") { tab_.toolsReady=YES; [owner_ syncToolsDockSide:tab_]; [owner_ inspectInTools:tab_]; }
        else if (kind=="dock" && tab_.toolsReady) {
            NSString *side=String(data->GetString("value"));
            [owner_ applyToolsPosition:[side isEqual:@"undocked"]?@"window":side];
        }
        else if (kind=="close") [owner_ closeTools:tab_];
        else if (kind=="copy") {
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:String(data->GetString("value")) forType:NSPasteboardTypeString];
        } else if (kind=="open") {
            NSString *address=String(data->GetString("value"));
            if (SLAllowedNavigation(address)) [owner_ addTabURL:address];
        }
        return true;
    }
    bool DoClose(CefRefPtr<CefBrowser>) override {
        for (NSView *view in [tab_.toolsContainer.subviews copy]) [view removeFromSuperview];
        return true;
    }
    void OnBeforeClose(CefRefPtr<CefBrowser>) override {
        if (tab_->toolsConnection) tab_->toolsConnection->Close();
        tab_->toolsConnection=nullptr; tab_->toolsBrowser=nullptr;
        [tab_.toolsContainer removeFromSuperview]; tab_.toolsContainer=nil;
        [owner_ toolsClosed:tab_];
    }
private:
    __weak SLController *owner_;
    __strong SLTab *tab_;
    IMPLEMENT_REFCOUNTING(DockClient);
};
