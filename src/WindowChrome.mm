#import "WindowChrome.h"
#include <initializer_list>

const CGFloat SLToolbarHeight=56;

@interface SLWindowChrome ()
@property (weak) NSWindow *window;
@property NSArray<NSValue *> *nativeButtonFrames;
@property CGFloat nativeTitlebarHeight;
@property BOOL transitioning;
@property BOOL layingOut;
@end

@implementation SLWindowChrome
- (instancetype)initWithWindow:(NSWindow *)window {
    if ((self=[super init])) {
        _window=window;
        NSMutableArray *frames=[NSMutableArray array];
        for (NSWindowButton type : {NSWindowCloseButton,NSWindowMiniaturizeButton,NSWindowZoomButton}) {
            NSButton *button=[window standardWindowButton:type];
            if (!button) return nil;
            [frames addObject:[NSValue valueWithRect:button.frame]];
        }
        _nativeButtonFrames=frames;
        _nativeTitlebarHeight=NSHeight([window standardWindowButton:NSWindowCloseButton].superview.superview.frame);
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(nativeFrameChanged:) name:NSViewFrameDidChangeNotification object:nil];
    }
    return self;
}
- (void)nativeFrameChanged:(NSNotification *)notification {
    if (_layingOut || _transitioning) return;
    NSView *view=notification.object;
    NSButton *close=[_window standardWindowButton:NSWindowCloseButton];
    if (view==close.superview || view==close.superview.superview || view==close ||
        view==[_window standardWindowButton:NSWindowMiniaturizeButton] || view==[_window standardWindowButton:NSWindowZoomButton]) [self layout];
}
- (void)applyLayout:(BOOL)custom {
    if (_layingOut) return;
    // AppKit can recreate these views; fetch the current hierarchy each time.
    NSButton *close=[_window standardWindowButton:NSWindowCloseButton];
    NSView *container=close.superview.superview;
    NSView *root=_window.contentView;
    if (!container.superview || !root) return;
    _layingOut=YES;
    // AppKit can reposition the native titlebar during appearance/layout updates
    // after NSWindowDidUpdate. Keep the actual controls aligned on those changes.
    close.superview.postsFrameChangedNotifications=YES;
    container.postsFrameChangedNotifications=YES;
    CGFloat height=custom?SLToolbarHeight:_nativeTitlebarHeight;
    NSRect header=NSMakeRect(0,root.isFlipped?0:NSHeight(root.bounds)-height,NSWidth(root.bounds),height);
    NSRect frame=[root convertRect:header toView:container.superview];
    // Grow the native titlebar too, so the buttons remain fully hit-testable.
    if (!NSEqualRects(container.frame,frame)) container.frame=frame;
    NSUInteger index=0;
    CGFloat firstX=NSMinX(_nativeButtonFrames.firstObject.rectValue);
    BOOL rtl=_window.windowTitlebarLayoutDirection==NSUserInterfaceLayoutDirectionRightToLeft;
    for (NSWindowButton type : {NSWindowCloseButton,NSWindowMiniaturizeButton,NSWindowZoomButton}) {
        NSButton *button=[_window standardWindowButton:type];
        NSRect native=_nativeButtonFrames[index++].rectValue;
        if (!button) continue;
        button.postsFrameChangedNotifications=YES;
        NSRect target=custom?button.frame:native;
        if (custom) {
            // Preserve native button sizes and spacing; only move the group.
            CGFloat x=rtl?NSWidth(root.bounds)-18-NSWidth(target)+NSMinX(native)-firstX:18+NSMinX(native)-firstX;
            NSPoint center=[root convertPoint:NSMakePoint(x,root.isFlipped?height/2:NSHeight(root.bounds)-height/2) toView:button.superview];
            target.origin=NSMakePoint(center.x,center.y-NSHeight(target)/2);
        }
        if (!NSEqualRects(button.frame,target)) button.frame=target;
    }
    _layingOut=NO;
}
- (void)layout {
    if (!_transitioning && !(_window.styleMask & NSWindowStyleMaskFullScreen)) [self applyLayout:YES];
}
- (void)beginFullScreenTransition {
    _transitioning=YES;
    [self applyLayout:NO];
}
- (void)endFullScreenTransition {
    _transitioning=NO;
    [self layout];
}
@end
