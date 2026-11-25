#pragma once
#import "Shield.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_resource_request_handler.h"

class ShieldResource final : public CefResourceRequestHandler {
public:
    explicit ShieldResource(CefString site) : site_(site) {}
    ReturnValue OnBeforeResourceLoad(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
        CefRefPtr<CefRequest> request, CefRefPtr<CefCallback>) override {
        if (request->GetResourceType()==RT_MAIN_FRAME) return RV_CONTINUE;
        @autoreleasepool {
            NSString *url=[NSString stringWithUTF8String:request->GetURL().ToString().c_str()];
            NSString *site=[NSString stringWithUTF8String:site_.ToString().c_str()];
            return SLShieldShouldBlock(url,site) ? RV_CANCEL : RV_CONTINUE;
        }
    }
private:
    CefString site_;
    IMPLEMENT_REFCOUNTING(ShieldResource);
};
class ShieldRequests final : public CefRequestContextHandler {
public:
    explicit ShieldRequests(void (^ready)()=nil) : ready_([ready copy]) {}
    void OnRequestContextInitialized(CefRefPtr<CefRequestContext>) override { if (ready_) { ready_(); ready_=nil; } }
    CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
        CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, CefRefPtr<CefRequest> request,
        bool, bool, const CefString &initiator, bool&) override {
        // Worker requests can have no browser or Referer. Preserve their
        // initiating origin so they receive the same network protection.
        CefString site=browser && browser->GetMainFrame() ? browser->GetMainFrame()->GetURL() : CefString();
        if (site.empty()) site=request->GetReferrerURL();
        if (site.empty()) site=initiator;
        return new ShieldResource(site);
    }
private:
    void (^ready_)();
    IMPLEMENT_REFCOUNTING(ShieldRequests);
};
