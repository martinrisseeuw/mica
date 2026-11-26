#import <Cocoa/Cocoa.h>

@interface SLSidebarResizeHandle : NSView
@property (copy) void (^resizeBy)(CGFloat delta, BOOL finished);
@property CGFloat sidebarWidth;
@end

@protocol SLAddressActions <NSObject>
- (void)openAddress:(id)sender;
- (void)copyPageAddress:(id)sender;
- (void)dismissAddress:(id)sender;
@end

@interface SLAddressPanel : NSPanel
@property (readonly) NSButton *linkCopyButton;
- (instancetype)initWithAddress:(NSTextField *)address target:(id<SLAddressActions>)target;
@end
