#import <Cocoa/Cocoa.h>

// Native, renderer-free new-tab surface. The controller owns navigation and
// history completion; this view only owns presentation and responsive layout.
@interface SLStartPage : NSView
@property (readonly) NSTextField *address;
- (void)setPinnedItems:(NSArray<NSDictionary *> *)items;
- (instancetype)initWithFrame:(NSRect)frame target:(id)target;
@end
