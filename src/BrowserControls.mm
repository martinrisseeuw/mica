#import "BrowserControls.h"
#import "Appearance.h"

@interface SLSidebarResizeHandle ()
@property BOOL hovered;
@property BOOL dragging;
@property CGFloat startX;
@end
@implementation SLSidebarResizeHandle
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor]; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInActiveApp|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event { _hovered=YES; self.needsDisplay=YES; }
- (void)mouseExited:(NSEvent *)event { _hovered=NO; self.needsDisplay=YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (void)drawRect:(NSRect)rect {
    [SLThemeColor(_hovered || _dragging?SLAccent:SLBorder) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect((NSWidth(self.bounds)-4)/2,(NSHeight(self.bounds)-34)/2,4,34) xRadius:2 yRadius:2] fill];
}
- (void)mouseDown:(NSEvent *)event {
    _startX=[self.window convertPointToScreen:event.locationInWindow].x;
    _dragging=YES; self.needsDisplay=YES;
    if (_resizeBy) _resizeBy(0,NO);
}
- (void)mouseDragged:(NSEvent *)event {
    if (_dragging && _resizeBy) _resizeBy([self.window convertPointToScreen:event.locationInWindow].x-_startX,NO);
}
- (void)mouseUp:(NSEvent *)event {
    if (!_dragging) return;
    _dragging=NO; self.needsDisplay=YES;
    if (_resizeBy) _resizeBy([self.window convertPointToScreen:event.locationInWindow].x-_startX,YES);
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilitySplitterRole; }
- (NSString *)accessibilityLabel { return @"Sidebar width"; }
- (id)accessibilityValue { return @(_sidebarWidth); }
- (id)accessibilityMinValue { return @160; }
- (id)accessibilityMaxValue { return @360; }
- (BOOL)accessibilityPerformIncrement { if (_resizeBy) { _resizeBy(0,NO); _resizeBy(16,YES); } return YES; }
- (BOOL)accessibilityPerformDecrement { if (_resizeBy) { _resizeBy(0,NO); _resizeBy(-16,YES); } return YES; }
@end

@interface SLAddressSurface : NSView
@property NSTextField *address;
@property NSTextField *heading;
@property NSTextField *shortcut;
@property NSTextField *hint;
@property NSTextField *escape;
@property NSButton *openButton;
@property NSButton *closeButton;
@property NSButton *linkCopyButton;
@end
@implementation SLAddressSurface
- (BOOL)isFlipped { return YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (void)drawRect:(NSRect)rect {
    NSBezierPath *surface=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0.5,0.5) xRadius:12 yRadius:12];
    [SLThemeColor(SLSurface) setFill]; [surface fill]; [SLThemeColor(SLPopoverBorder) setStroke]; [surface stroke];
    NSBezierPath *input=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(15,47,NSWidth(self.bounds)-30,44) xRadius:8 yRadius:8];
    input.lineWidth=2; [SLThemeColor(SLAccent) setStroke]; [input stroke];
}
- (void)layout {
    [super layout]; CGFloat width=NSWidth(self.bounds);
    _heading.frame=NSMakeRect(14,14,width-100,20);
    _shortcut.frame=NSMakeRect(width-66,15,25,18);
    _closeButton.frame=NSMakeRect(width-37,11,26,26);
    _address.frame=NSMakeRect(26,59,width-84,22);
    _openButton.frame=NSMakeRect(width-53,55,28,28);
    _linkCopyButton.frame=NSMakeRect(14,104,104,30);
    _hint.frame=NSMakeRect(132,110,MAX(0,width-240),18);
    _escape.frame=NSMakeRect(width-94,110,80,18);
}
@end

@interface SLAddressPanel ()
@property (weak) id<SLAddressActions> actionTarget;
@end
@implementation SLAddressPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)cancelOperation:(id)sender { [_actionTarget dismissAddress:sender]; }
- (NSButton *)linkCopyButton { return ((SLAddressSurface *)self.contentView).linkCopyButton; }
- (instancetype)initWithAddress:(NSTextField *)address target:(id<SLAddressActions>)target {
    if ((self=[super initWithContentRect:NSMakeRect(0,0,680,148) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO])) {
        _actionTarget=target; self.releasedWhenClosed=NO; self.opaque=NO;
        self.backgroundColor=NSColor.clearColor; self.hasShadow=YES; self.hidesOnDeactivate=YES;
        self.becomesKeyOnlyIfNeeded=NO; self.floatingPanel=NO;
        self.collectionBehavior=NSWindowCollectionBehaviorFullScreenAuxiliary;
        SLAddressSurface *surface=[[SLAddressSurface alloc] initWithFrame:NSMakeRect(0,0,680,148)];
        surface.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        surface.address=address; [surface addSubview:address];
        NSTextField *(^label)(NSString *,CGFloat)=^NSTextField *(NSString *text,CGFloat size) {
            NSTextField *field=[NSTextField labelWithString:text]; field.font=[NSFont systemFontOfSize:size];
            field.textColor=SLThemeColor(SLSecondaryText); [surface addSubview:field]; return field;
        };
        surface.heading=label(@"Page address",13); surface.heading.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]; surface.heading.textColor=SLThemeColor(SLText);
        surface.shortcut=label(@"⌘L",12);
        surface.hint=label(@"Return to open in this tab",12);
        surface.escape=label(@"Esc to close",12); surface.escape.alignment=NSTextAlignmentRight;
        NSButton *(^button)(NSString *,NSString *,SEL)=^NSButton *(NSString *symbol,NSString *name,SEL action) {
            NSButton *control=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil] target:target action:action];
            control.bordered=NO; control.toolTip=name; control.accessibilityLabel=name; control.contentTintColor=SLThemeColor(SLText);
            [surface addSubview:control]; return control;
        };
        surface.closeButton=button(@"xmark",@"Close address editor",@selector(dismissAddress:));
        surface.openButton=button(@"arrow.right",@"Open address in this tab",@selector(openAddress:));
        surface.linkCopyButton=button(@"doc.on.doc",@"Copy current page link",@selector(copyPageAddress:));
        surface.linkCopyButton.title=@"Copy link"; surface.linkCopyButton.imagePosition=NSImageLeft;
        surface.linkCopyButton.font=[NSFont systemFontOfSize:13]; surface.linkCopyButton.bordered=YES; surface.linkCopyButton.bezelStyle=NSBezelStyleRounded;
        self.title=@"Page address";
        self.contentView=surface; surface.needsLayout=YES; [surface layoutSubtreeIfNeeded];
    }
    return self;
}
@end
