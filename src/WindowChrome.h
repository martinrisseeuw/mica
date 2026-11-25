#import <Cocoa/Cocoa.h>

FOUNDATION_EXPORT const CGFloat SLToolbarHeight;

// Keeps the real AppKit buttons aligned with Mica's custom toolbar.
@interface SLWindowChrome : NSObject
- (instancetype)initWithWindow:(NSWindow *)window;
- (void)layout;
- (void)beginFullScreenTransition;
- (void)endFullScreenTransition;
@end
