// The normal disposable-profile gate must pass before installing these doubles.
// Exercise real CEF navigation and AppKit sheets without launching any real app.
- (NSString *)appLinksSheetText {
    NSMutableString *text=[NSMutableString string];
    if (!_window.attachedSheet) return text;
    NSMutableArray<NSView *> *views=[NSMutableArray arrayWithObject:_window.attachedSheet.contentView];
    for (NSUInteger i=0;i<views.count;i++) {
        NSView *view=views[i]; [views addObjectsFromArray:view.subviews];
        if ([view isKindOfClass:NSTextField.class]) [text appendString:((NSTextField *)view).stringValue];
    }
    return text;
}
- (void)appLinksEvaluate:(NSString *)script gesture:(BOOL)gesture {
    auto params=CefDictionaryValue::Create();
    params->SetString("expression",script.UTF8String); params->SetBool("userGesture",gesture);
    _activeTab->browser->GetHost()->ExecuteDevToolsMethod(9700+(int)_smokeTicks,"Runtime.evaluate",params);
}
- (void)appLinksSmokeTick {
    static NSURL *openedURL;
    static NSUInteger opens=0, baselineTabs=0;
    static NSInteger waitUntil=0;
    static BOOL failOpen=NO;
    NSString *callback=@"claude://login/callback?code=synthetic%2Bvalue&state=a%2Fb#done";
    if (_smokeStep==0 && !_activeTab.url.length) { [self navigate:_smokeURL]; return; }
    if (!_activeTab->browser || _activeTab.loading) return;
    switch (_smokeStep) {
        case 0:
            if (![_activeTab.title isEqual:@"App links fixture"]) return;
            baselineTabs=_activeSpace.tabs.count;
            method_setImplementation(class_getInstanceMethod(SLController.class,@selector(applicationForExternalURL:)),
                imp_implementationWithBlock(^NSURL *(id controller, NSURL *url) {
                    return [url.scheme isEqual:@"mica-unhandled-test"] ? nil : [NSURL fileURLWithPath:@"/System/Applications/Calculator.app"];
                }));
            method_setImplementation(class_getInstanceMethod(SLController.class,@selector(openExternalAppURL:application:completion:)),
                imp_implementationWithBlock(^(id controller, NSURL *url, NSURL *app, void (^completion)(NSError *)) {
                    openedURL=url; opens++;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(failOpen ? [NSError errorWithDomain:@"AppLinksSmoke" code:1 userInfo:nil] : nil);
                    });
                }));
            [self appLinksEvaluate:@"location.href=document.querySelector('#same').href; document.title='Automatic attempted'" gesture:NO];
            waitUntil=_smokeTicks+3; _smokeStep=1; break;
        case 1:
            if (_smokeTicks<waitUntil || ![_activeTab.title isEqual:@"Automatic attempted"]) return;
            if (_externalAppPromptPending || _window.attachedSheet || opens) { [self smokeFinish:@"Automatic navigation prompted or launched an app"]; return; }
            [_smokeChecks addObject:@"Automatic app links do not prompt or launch apps"];
            [self appLinksEvaluate:@"document.querySelector('#same').click()" gesture:YES]; _smokeStep=2; break;
        case 2: {
            if (!_window.attachedSheet) return;
            if (opens || _activeSpace.tabs.count!=baselineTabs || ![_activeTab.url hasPrefix:_smokeURL]) { [self smokeFinish:@"App handoff launched early or replaced the web tab"]; return; }
            NSString *text=[self appLinksSheetText];
            if (![text containsString:@"Calculator"] || ![text containsString:@"127.0.0.1"] || [text containsString:@"synthetic"] || [text containsString:@"private"]) { [self smokeFinish:@"Confirmation did not identify app/site or exposed callback data"]; return; }
            [_smokeChecks addObject:@"A real page link shows native app/site confirmation without callback tokens"];
            [_window endSheet:_window.attachedSheet returnCode:NSAlertFirstButtonReturn]; _smokeStep=3; break;
        }
        case 3:
            if (_externalAppPromptPending || _window.attachedSheet) return;
            if (opens) { [self smokeFinish:@"Cancel opened the app"]; return; }
            [_smokeChecks addObject:@"Cancel leaves the app unopened and the web page intact"];
            [self appLinksEvaluate:@"document.querySelector('#same').click()" gesture:YES]; _smokeStep=4; break;
        case 4:
            if (!_window.attachedSheet) return;
            [_window endSheet:_window.attachedSheet returnCode:NSAlertSecondButtonReturn]; _smokeStep=5; break;
        case 5:
            if (_externalAppPromptPending || _window.attachedSheet) return;
            if (opens!=1 || ![openedURL.absoluteString isEqual:callback]) { [self smokeFinish:@"Confirmed handoff did not preserve the complete callback URL"]; return; }
            [_smokeChecks addObject:@"Open App passes the exact encoded callback URL to the launcher once"];
            [self appLinksEvaluate:@"document.querySelector('#popup').click()" gesture:YES]; _smokeStep=6; break;
        case 6:
            if (!_window.attachedSheet) return;
            if (_activeSpace.tabs.count!=baselineTabs) { [self smokeFinish:@"An app link popup left an empty tab"]; return; }
            [_window endSheet:_window.attachedSheet returnCode:NSAlertSecondButtonReturn]; _smokeStep=7; break;
        case 7:
            if (_externalAppPromptPending || _window.attachedSheet) return;
            if (opens!=2 || ![openedURL.absoluteString isEqual:callback]) { [self smokeFinish:@"A target=_blank app link did not hand off correctly"]; return; }
            [_smokeChecks addObject:@"New-window app links confirm and launch without creating an empty tab"];
            [self appLinksEvaluate:@"document.querySelector('#script').click()" gesture:YES]; _smokeStep=8; break;
        case 8:
            if (!_window.attachedSheet) return;
            // A second request must not queue another prompt while one is visible.
            [self requestExternalAppURL:callback fromTab:_activeTab origin:_smokeURL];
            [_window endSheet:_window.attachedSheet returnCode:NSAlertSecondButtonReturn]; _smokeStep=9; break;
        case 9:
            if (_externalAppPromptPending || _window.attachedSheet) return;
            if (opens!=3) { [self smokeFinish:@"Scripted button or duplicate suppression failed"]; return; }
            [_smokeChecks addObject:@"A scripted Open App button works; duplicate requests do not queue prompts"];
            [self appLinksEvaluate:@"document.querySelector('#missing').click()" gesture:YES]; _smokeStep=10; break;
        case 10:
            if (!_window.attachedSheet) return;
            if (![[self appLinksSheetText] containsString:@"No app can open this link"]) { [self smokeFinish:@"Missing handler explanation was not shown"]; return; }
            [_window endSheet:_window.attachedSheet returnCode:NSAlertFirstButtonReturn]; _smokeStep=11; break;
        case 11:
            if (_externalAppPromptPending || _window.attachedSheet) return;
            if (opens!=3) { [self smokeFinish:@"An unhandled protocol launched an app"]; return; }
            [_smokeChecks addObject:@"Missing app handlers show a dismissible explanation"];
            [self appLinksEvaluate:@"document.querySelector('#same').click()" gesture:YES]; _smokeStep=12; break;
        case 12:
            if (!_window.attachedSheet) return;
            _activeTab.navigationGeneration++;
            [_window endSheet:_window.attachedSheet returnCode:NSAlertSecondButtonReturn]; _smokeStep=13; break;
        case 13:
            if (_externalAppPromptPending || _window.attachedSheet) return;
            if (opens!=3) { [self smokeFinish:@"An outdated confirmation launched an app"]; return; }
            [_smokeChecks addObject:@"A changed page invalidates its pending confirmation"];
            failOpen=YES;
            [self appLinksEvaluate:@"document.querySelector('#same').click()" gesture:YES]; _smokeStep=14; break;
        case 14:
            if (!_window.attachedSheet) return;
            [_window endSheet:_window.attachedSheet returnCode:NSAlertSecondButtonReturn]; _smokeStep=15; break;
        case 15:
            if (!_window.attachedSheet || opens!=4) return;
            if (![[self appLinksSheetText] containsString:@"Couldn’t open Calculator"]) return;
            [_window endSheet:_window.attachedSheet returnCode:NSAlertFirstButtonReturn]; _smokeStep=16; break;
        case 16:
            if (_window.attachedSheet) return;
            [_smokeChecks addObject:@"Launch failures show an explanation without exposing the callback URL"];
            [self appLinksEvaluate:@"document.querySelector('#frame').src=document.querySelector('#same').href; document.title='Iframe attempted'" gesture:YES];
            waitUntil=_smokeTicks+3; _smokeStep=17; break;
        case 17:
            if (_smokeTicks<waitUntil || ![_activeTab.title isEqual:@"Iframe attempted"]) return;
            if (_externalAppPromptPending || _window.attachedSheet || opens!=4 || _activeSpace.tabs.count!=baselineTabs || _activeTab.error) { [self smokeFinish:@"Subframe app link escaped its boundary or changed the web page"]; return; }
            [_smokeChecks addObject:@"Subframe-only navigation cannot request app handoff; the web page remains usable"];
            [self appLinksEvaluate:@"document.querySelector('#frame').src=document.querySelector('#frame').dataset.url" gesture:NO];
            _smokeStep=18; break;
        case 18:
            if (![_activeTab.title isEqual:@"Frame ready"]) return;
            for (NSString *type in @[@"mousePressed",@"mouseReleased"]) {
                auto params=CefDictionaryValue::Create(); params->SetString("type",type.UTF8String);
                params->SetDouble("x",50); params->SetDouble("y",215);
                params->SetString("button","left"); params->SetInt("clickCount",1);
                _activeTab->browser->GetHost()->ExecuteDevToolsMethod(9900+(int)_smokeTicks,"Input.dispatchMouseEvent",params);
            }
            waitUntil=_smokeTicks+3; _smokeStep=19; break;
        case 19:
            if (_smokeTicks<waitUntil) return;
            if (!_window.attachedSheet || opens!=4 || ![[self appLinksSheetText] containsString:@"A link in this tab"] || ![[self appLinksSheetText] containsString:@"Current website:"]) { [self smokeFinish:@"Embedded top navigation bypassed consent or misattributed its initiating website"]; return; }
            [_window endSheet:_window.attachedSheet returnCode:NSAlertFirstButtonReturn]; _smokeStep=20; break;
        case 20:
            if (_externalAppPromptPending || _window.attachedSheet) return;
            if (opens!=4) { [self smokeFinish:@"Cancelling an embedded app link opened the app"]; return; }
            [_smokeChecks addObject:@"Embedded top navigation requires consent and labels the current tab without claiming its initiator"];
            failOpen=NO;
            [self appLinksEvaluate:@"document.querySelector('#redirect').click()" gesture:YES]; _smokeStep=21; break;
        case 21:
            if (!_window.attachedSheet) return;
            [_window endSheet:_window.attachedSheet returnCode:NSAlertSecondButtonReturn]; _smokeStep=22; break;
        case 22:
            if (_externalAppPromptPending || _window.attachedSheet) return;
            if (opens!=5 || ![openedURL.absoluteString isEqual:callback] || _activeTab.error) { [self smokeFinish:@"User-initiated HTTP redirect did not hand off the callback"]; return; }
            [_smokeChecks addObject:@"A clicked HTTP redirect can hand off the app callback after consent"];
            [self smokeFinish:nil]; break;
    }
}
