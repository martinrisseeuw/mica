#pragma once
#include "include/cef_browser.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_parser.h"

// One private CDP request, attached only to the selected extension's page.
// No remote-debugging port, website bridge, or credential extraction.
class SLExtensionImportBridge final : public CefDevToolsMessageObserver {
public:
    void Start(CefRefPtr<CefBrowser> browser, NSString *script, void (^completion)(BOOL)) {
        browser_=browser; completion_=[completion copy];
        registration_=browser_->GetHost()->AddDevToolsMessageObserver(this);
        static int next=700000000; message_=++next;
        auto params=CefDictionaryValue::Create(); params->SetString("expression",script.UTF8String);
        params->SetBool("awaitPromise",true); params->SetBool("returnByValue",true);
        browser_->GetHost()->ExecuteDevToolsMethod(message_,"Runtime.evaluate",params);
    }
    void Cancel() { completion_=nil; registration_=nullptr; browser_=nullptr; }
    void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int id, bool success, const void *bytes, size_t size) override {
        if (id!=message_) return;
        NSDictionary *response=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:size] options:0 error:nil];
        BOOL passed=success && !response[@"exceptionDetails"] && [response[@"result"][@"value"] isEqual:@YES];
        auto self=CefRefPtr<SLExtensionImportBridge>(this);
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^completion)(BOOL)=self->completion_; self->Cancel(); if (completion) completion(passed);
        });
    }
private:
    int message_=0;
    CefRefPtr<CefBrowser> browser_;
    CefRefPtr<CefRegistration> registration_;
    void (^completion_)(BOOL)=nil;
    IMPLEMENT_REFCOUNTING(SLExtensionImportBridge);
};
