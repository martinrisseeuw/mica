#import <Cocoa/Cocoa.h>

@interface SLUpdates : NSObject <NSMenuItemValidation>
- (instancetype)initWithEnabled:(BOOL)enabled;
- (void)start;
- (void)checkForUpdates:(id)sender;
- (void)toggleAutomaticUpdates:(id)sender;
@property (readonly) BOOL started;
@end
