#import <Cocoa/Cocoa.h>

@interface SLController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate, NSSearchFieldDelegate>
- (instancetype)initWithProfile:(NSString *)profile updatesEnabled:(BOOL)updatesEnabled;
- (void)start;
- (void)requestQuit;
- (void)openExternalURLArguments:(NSArray<NSString *> *)arguments;
- (void)handleOpenURLEvent:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply;
@end
