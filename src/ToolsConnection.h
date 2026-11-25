#pragma once
#include "include/cef_devtools_message_observer.h"
#include <set>
#include <vector>

// Each dock owns a separate CDP session. Destroying an observer alone does NOT
// detach CEF's root agent; a child session lets close reset breakpoints,
// interception, emulation and paused execution without reloading the page.
class ToolsConnection final : public CefDevToolsMessageObserver {
public:
    ToolsConnection(SLController *owner, SLTab *tab, CefRefPtr<CefBrowser> frontend)
        : owner_(owner), tab_(tab), inspected_(tab->browser), frontend_(frontend) {}
    void Start() {
        registration_=inspected_->GetHost()->AddDevToolsMessageObserver(this);
        infoID_=NextID(); Command(infoID_,"Target.getTargetInfo",nullptr);
    }
    void Send(const std::string &message) {
        if (closing_) return;
        if (session_.empty()) {
            if (pending_.size()<1024) pending_.push_back(message);
            return;
        }
        auto value=CefParseJSON(message,JSON_PARSER_RFC);
        if (!value || value->GetType()!=VTYPE_DICTIONARY) return;
        auto data=value->GetDictionary();
        if (!data->HasKey("sessionId")) data->SetString("sessionId",session_);
        else if (!sessions_.count(data->GetString("sessionId").ToString())) return;
        std::string encoded=CefWriteJSON(value,JSON_WRITER_DEFAULT);
        Dispatch(encoded,false);
    }
    void Close() {
        CefRefPtr<ToolsConnection> keepAlive=this;
        closing_=true; frontend_=nullptr; pending_.clear();
        if (!inspected_) return;
        if (!session_.empty()) {
            auto params=CefDictionaryValue::Create(); params->SetString("sessionId",session_);
            Command(NextID(),"Target.detachFromTarget",params);
            Finish();
        } else if (!infoID_ && !attachID_) Finish();
        // A pending handshake retains this observer until its result arrives,
        // then immediately detaches. This also covers closing during startup.
    }
    bool OnDevToolsMessage(CefRefPtr<CefBrowser>, const void *bytes, size_t size) override {
        CefRefPtr<ToolsConnection> keepAlive=this;
        auto value=CefParseJSON(bytes,size,JSON_PARSER_RFC);
        if (!value || value->GetType()!=VTYPE_DICTIONARY) return true;
        auto data=value->GetDictionary();
        if (!data->HasKey("sessionId")) {
            int id=data->GetInt("id");
            if (infoID_ && id==infoID_) {
                infoID_=0;
                if (closing_) { Finish(); return true; }
                auto result=data->GetDictionary("result");
                auto info=result ? result->GetDictionary("targetInfo") : nullptr;
                if (!info) { Fail(); return true; }
                auto params=CefDictionaryValue::Create();
                params->SetString("targetId",info->GetString("targetId")); params->SetBool("flatten",true);
                attachID_=NextID(); Command(attachID_,"Target.attachToTarget",params);
            } else if (attachID_ && id==attachID_) {
                attachID_=0;
                auto result=data->GetDictionary("result");
                session_=result ? result->GetString("sessionId").ToString() : "";
                if (session_.empty()) { Fail(); return true; }
                sessions_.insert(session_);
                if (closing_) { Close(); return true; }
                auto messages=std::move(pending_); pending_.clear();
                for (const auto &message : messages) Send(message);
            }
            return true;
        }
        std::string session=data->GetString("sessionId");
        if (closing_ || !frontend_ || !sessions_.count(session)) return true;
        auto params=data->GetDictionary("params");
        std::string method=data->GetString("method");
        if (params && method=="Target.attachedToTarget") sessions_.insert(params->GetString("sessionId").ToString());
        if (params && method=="Target.detachedFromTarget") sessions_.erase(params->GetString("sessionId").ToString());
        if (session==session_) data->Remove("sessionId");
        auto message=CefProcessMessage::Create("Searchlight.Protocol");
        message->GetArgumentList()->SetString(0,CefWriteJSON(value,JSON_WRITER_DEFAULT));
        frontend_->GetMainFrame()->SendProcessMessage(PID_RENDERER,message);
        tab_.toolsMessages++;
        return true;
    }
    void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {
        CefRefPtr<ToolsConnection> keepAlive=this;
        closing_=true; Finish();
    }
private:
    static int NextID() { static int id=1000000000; return id++; } // UI thread only.
    void Command(int id, const char *method, CefRefPtr<CefDictionaryValue> params) {
        auto data=CefDictionaryValue::Create(); data->SetInt("id",id); data->SetString("method",method);
        if (params) data->SetDictionary("params",params);
        auto value=CefValue::Create(); value->SetDictionary(data);
        std::string message=CefWriteJSON(value,JSON_WRITER_DEFAULT);
        Dispatch(message,true);
    }
    void Dispatch(std::string message, bool handshake) {
        // CEF's observer list forbids synchronous protocol reentry from a
        // response callback. Keep every outgoing call on the next UI turn.
        CefRefPtr<ToolsConnection> self=this;
        CefRefPtr<CefBrowser> browser=inspected_;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!browser || !browser->IsValid()) { self->Finish(); return; }
            if (!handshake && self->closing_) return;
            browser->GetHost()->SendDevToolsMessage(message.data(),message.size());
        });
    }
    void Finish() {
        registration_=nullptr; inspected_=nullptr; frontend_=nullptr; pending_.clear();
        session_.clear(); sessions_.clear(); infoID_=0; attachID_=0;
    }
    void Fail() {
        owner_.status.stringValue=@"Couldn’t connect DevTools. Try the Window position.";
        Finish();
        [owner_ closeTools:tab_];
    }
    __weak SLController *owner_;
    __weak SLTab *tab_;
    CefRefPtr<CefBrowser> inspected_, frontend_;
    CefRefPtr<CefRegistration> registration_;
    std::string session_;
    std::set<std::string> sessions_;
    std::vector<std::string> pending_;
    int infoID_=0, attachID_=0;
    bool closing_=false;
    IMPLEMENT_REFCOUNTING(ToolsConnection);
};
