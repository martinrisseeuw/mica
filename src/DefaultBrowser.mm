#import "DefaultBrowser.h"

BOOL SLIsDefaultBrowser(void) {
    for (NSString *scheme in @[@"http",@"https"]) {
        NSURL *handler=[NSWorkspace.sharedWorkspace URLForApplicationToOpenURL:[NSURL URLWithString:[scheme stringByAppendingString:@"://example.com/"]]];
        if (!handler || ![[NSBundle bundleWithURL:handler].bundleIdentifier isEqual:NSBundle.mainBundle.bundleIdentifier]) return NO;
    }
    return YES;
}
void SLRequestDefaultBrowser(void (^completion)(NSError *error)) {
    NSURL *app=NSBundle.mainBundle.bundleURL;
    // Launch Services owns consent; run only after the user chooses the menu action.
    [NSWorkspace.sharedWorkspace setDefaultApplicationAtURL:app toOpenURLsWithScheme:@"http" completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { completion(error); return; }
            [NSWorkspace.sharedWorkspace setDefaultApplicationAtURL:app toOpenURLsWithScheme:@"https" completionHandler:^(NSError *secureError) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(secureError); });
            }];
        });
    }];
}
