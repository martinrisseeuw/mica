#pragma once
// Screenshot only the disposable test frontend through its own CDP session.
class ToolsCapture final : public CefDevToolsMessageObserver {
public:
    explicit ToolsCapture(SLController *owner) : owner_(owner) {}
    void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int id, bool success, const void *bytes, size_t size) override {
        if (id!=9001) return;
        NSData *json=[NSData dataWithBytes:bytes length:size];
        NSDictionary *result=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
        NSData *png=success ? [[NSData alloc] initWithBase64EncodedString:result[@"data"] ?: @"" options:0] : nil;
        NSString *path=[NSProcessInfo.processInfo.environment[@"SEARCHLIGHT_SMOKE_SCREENSHOT"] stringByDeletingLastPathComponent];
        owner_.smokeCaptured=png.length && [png writeToFile:[path stringByAppendingPathComponent:@"docked-devtools.png"] atomically:YES];
    }
private:
    __weak SLController *owner_;
    IMPLEMENT_REFCOUNTING(ToolsCapture);
};
