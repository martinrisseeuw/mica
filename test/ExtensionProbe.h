#pragma once
// Observe the extension's real isolated world; never inject a substitute script.
class ExtensionProbe final : public CefDevToolsMessageObserver {
public:
    explicit ExtensionProbe(SLController *owner) : owner_(owner) {}
    void OnDevToolsEvent(CefRefPtr<CefBrowser>, const CefString &method, const void *bytes, size_t size) override {
        if (method=="Debugger.scriptParsed") {
            NSDictionary *event=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:size] options:0 error:nil];
            if ([event[@"url"] isEqual:@"chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/inline/injected.js"]) owner_.extensionScriptLoaded=YES;
            return;
        }
        if (method.ToString()!="Runtime.executionContextCreated") return;
        NSDictionary *event=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:size] options:0 error:nil];
        NSString *origin=event[@"context"][@"origin"];
        if ([origin hasPrefix:@"chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa"]) owner_.extensionScriptReady=YES;
    }
private:
    __weak SLController *owner_;
    IMPLEMENT_REFCOUNTING(ExtensionProbe);
};
