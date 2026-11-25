#pragma once
#include "include/cef_app.h"
#include "include/cef_parser.h"
#include "include/cef_v8.h"
#include <map>

static bool SLTrustedToolsURL(const CefString &url) {
    const auto s=url.ToString();
    return s=="devtools://devtools/bundled/devtools_app.html" || s.rfind("devtools://devtools/bundled/devtools_app.html?",0)==0;
}
class ToolsSend final : public CefV8Handler {
public:
    bool Execute(const CefString&, CefRefPtr<CefV8Value>, const CefV8ValueList &args,
                 CefRefPtr<CefV8Value>&, CefString&) override {
        auto context=CefV8Context::GetCurrentContext();
        if (!context || !context->GetFrame()->IsMain() || !SLTrustedToolsURL(context->GetFrame()->GetURL()) || args.size()!=1 || !args[0]->IsString()) return false;
        auto message=CefProcessMessage::Create("Searchlight.Tools");
        message->GetArgumentList()->SetString(0,args[0]->GetStringValue());
        context->GetFrame()->SendProcessMessage(PID_BROWSER,message);
        return true;
    }
private:
    IMPLEMENT_REFCOUNTING(ToolsSend);
};
class RendererApp final : public CefApp, public CefRenderProcessHandler {
public:
    CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
    void OnBrowserCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDictionaryValue> extra) override {
        if (extra && extra->HasKey("searchlightToolsHost")) hosts_[browser->GetIdentifier()]=extra->GetString("searchlightToolsHost");
    }
    void OnBrowserDestroyed(CefRefPtr<CefBrowser> browser) override { hosts_.erase(browser->GetIdentifier()); }
    void OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context) override {
        auto it=hosts_.find(browser->GetIdentifier());
        if (it==hosts_.end() || !frame->IsMain() || !SLTrustedToolsURL(frame->GetURL())) return;
        context->GetGlobal()->SetValue("__slSend",CefV8Value::CreateFunction("__slSend",new ToolsSend),static_cast<cef_v8_propertyattribute_t>(V8_PROPERTY_ATTRIBUTE_READONLY|V8_PROPERTY_ATTRIBUTE_DONTDELETE));
        CefRefPtr<CefV8Value> result; CefRefPtr<CefV8Exception> error;
        context->Eval(it->second,frame->GetURL(),1,result,error);
    }
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefProcessId source, CefRefPtr<CefProcessMessage> message) override {
        if (source!=PID_BROWSER || message->GetName()!="Searchlight.Protocol" || !hosts_.count(browser->GetIdentifier()) || !frame->IsMain() || !SLTrustedToolsURL(frame->GetURL())) return false;
        auto value=CefValue::Create(); value->SetString(message->GetArgumentList()->GetString(0));
        frame->ExecuteJavaScript("globalThis.InspectorFrontendAPI?.dispatchMessage("+CefWriteJSON(value,JSON_WRITER_DEFAULT).ToString()+")",frame->GetURL(),1);
        return true;
    }
private:
    std::map<int,CefString> hosts_;
    IMPLEMENT_REFCOUNTING(RendererApp);
};
