#import "ExtensionPanel.h"
#import "Appearance.h"
#import <QuartzCore/QuartzCore.h>

void SLClipViewport(NSView *view, NSUInteger corners) {
    view.wantsLayer=YES; view.clipsToBounds=YES;
    BOOL flipped=view.isFlipped;
    CACornerMask mask=0;
    if (corners&1) mask|=flipped?kCALayerMinXMinYCorner:kCALayerMinXMaxYCorner;
    if (corners&2) mask|=flipped?kCALayerMaxXMinYCorner:kCALayerMaxXMaxYCorner;
    if (corners&4) mask|=flipped?kCALayerMinXMaxYCorner:kCALayerMinXMinYCorner;
    if (corners&8) mask|=flipped?kCALayerMaxXMaxYCorner:kCALayerMaxXMinYCorner;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    view.layer.masksToBounds=YES; view.layer.cornerRadius=8; view.layer.maskedCorners=mask;
    [CATransaction commit];
}

@interface SLGridCanvas : NSView
@property BOOL panelSurface;
- (void)updateSurfaceColors;
@end
@implementation SLGridCanvas
- (BOOL)isFlipped { return YES; }
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateSurfaceColors];
    self.needsDisplay=YES;
}
- (void)updateSurfaceColors {
    if (_panelSurface) {
        [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ self.layer.backgroundColor=SLThemeColor(SLSurface).CGColor; self.layer.borderColor=SLThemeColor(SLBorder).CGColor; }];
    }
}
@end

@interface SLGridButton : NSButton
@property BOOL hovered;
@property BOOL pinControl;
@end
@implementation SLGridButton
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event { _hovered=YES; self.needsDisplay=YES; }
- (void)mouseExited:(NSEvent *)event { _hovered=NO; self.needsDisplay=YES; }
- (void)drawRect:(NSRect)dirty {
    BOOL selected=self.state==NSControlStateValueOn;
    NSColor *fill=SLThemeColor(selected?SLSelection:(_hovered||self.highlighted?SLHover:SLTile));
    if (!_pinControl || selected || _hovered) { [fill setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:_pinControl?6:8 yRadius:_pinControl?6:8] fill]; }
    CGFloat size=_pinControl?12:24;
    SLDrawIcon(self.image,NSMakeRect((self.bounds.size.width-size)/2,(self.bounds.size.height-size)/2,size,size),YES);
    if (self.window.firstResponder==self) {
        [NSColor.keyboardFocusIndicatorColor setStroke]; NSBezierPath *ring=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:7 yRadius:7]; ring.lineWidth=2; [ring stroke];
    }
}
@end

@implementation SLExtensionPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)cancelOperation:(id)sender { [self.actionTarget hideExtensionMenu]; }
@end

static NSTextField *Label(NSString *text, CGFloat size) {
    NSTextField *label=[NSTextField labelWithString:text]; label.font=[NSFont systemFontOfSize:size]; label.textColor=SLThemeColor(SLText); return label;
}
NSButton *SLExtensionControl(NSView *root, NSString *identifier, SEL action) {
    if ([root isKindOfClass:NSButton.class] && [root.identifier isEqual:identifier] && ((NSButton *)root).action==action) return (NSButton *)root;
    for (NSView *child in root.subviews) { NSButton *found=SLExtensionControl(child,identifier,action); if (found) return found; }
    return nil;
}

NSView *SLExtensionGrid(NSArray<NSDictionary *> *actions, NSArray<NSString *> *pins, id<SLExtensionActions> target) {
    NSUInteger count=actions.count+1, rows=(count+3)/4;
    CGFloat fullHeight=rows*86-8, gridHeight=MIN(fullHeight,336);
    SLGridCanvas *root=[[SLGridCanvas alloc] initWithFrame:NSMakeRect(0,0,312,102+gridHeight)];
    root.panelSurface=YES; root.wantsLayer=YES; root.layer.cornerRadius=14; root.layer.borderWidth=0.5; [root updateSurfaceColors];
    NSTextField *heading=Label(@"Extensions",14); heading.font=[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold]; heading.frame=NSMakeRect(16,16,160,20); [root addSubview:heading];
    NSButton *manage=[NSButton buttonWithTitle:@"Manage" target:target action:@selector(showExtensions:)]; manage.bordered=NO; manage.font=[NSFont systemFontOfSize:12]; manage.contentTintColor=SLThemeColor(SLSecondaryText); manage.frame=NSMakeRect(238,16,58,20); [root addSubview:manage];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(16,52,280,gridHeight)]; scroll.drawsBackground=NO; scroll.hasVerticalScroller=fullHeight>gridHeight; scroll.autohidesScrollers=YES; scroll.scrollerStyle=NSScrollerStyleOverlay;
    SLGridCanvas *grid=[[SLGridCanvas alloc] initWithFrame:NSMakeRect(0,0,280,fullHeight)]; scroll.documentView=grid; [root addSubview:scroll];
    NSView *first=nil, *previous=manage;
    for (NSUInteger i=0;i<count;i++) {
        BOOL add=i==actions.count; NSDictionary *item=add?nil:actions[i];
        CGFloat x=(i%4)*72, y=(i/4)*86;
        SLGridButton *button=[[SLGridButton alloc] initWithFrame:NSMakeRect(x,y,64,56)]; button.bordered=NO; button.imagePosition=NSImageOnly;
        button.identifier=add?@"add-extension":item[@"id"]; button.target=target; button.action=add?@selector(browseExtensions:):@selector(openExtensionButton:);
        button.image=add?[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil]:(item[@"image"] ?: [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension" accessibilityDescription:nil]);
        NSString *title=add?@"Add":item[@"name"]; button.toolTip=add?@"Add extension":[@"Open " stringByAppendingString:title]; button.accessibilityLabel=button.toolTip;
        [grid addSubview:button]; if (!first) first=button; previous.nextKeyView=button; previous=button;
        if (!add) {
            BOOL pinned=[pins containsObject:item[@"id"]];
            SLGridButton *pin=[[SLGridButton alloc] initWithFrame:NSMakeRect(x+44,y+36,20,20)]; pin.pinControl=YES; pin.bordered=NO;
            pin.state=pinned?NSControlStateValueOn:NSControlStateValueOff; pin.identifier=item[@"id"]; pin.target=target; pin.action=@selector(toggleExtensionPin:);
            pin.image=[NSImage imageWithSystemSymbolName:pinned?@"pin.fill":@"pin" accessibilityDescription:nil];
            pin.toolTip=[NSString stringWithFormat:@"%@ %@",pinned?@"Unpin":@"Pin",title]; pin.accessibilityLabel=pin.toolTip; pin.accessibilityValue=pinned?@"Pinned":@"Not pinned";
            [grid addSubview:pin]; previous.nextKeyView=pin; previous=pin;
        }
        NSTextField *label=Label(title,11); label.alignment=NSTextAlignmentCenter; label.lineBreakMode=NSLineBreakByTruncatingTail; label.frame=NSMakeRect(x,y+62,64,16); label.toolTip=title; [grid addSubview:label];
    }
    previous.nextKeyView=manage; manage.nextKeyView=first;
    NSButton *import=[NSButton buttonWithTitle:@"Import…" target:target action:@selector(importChromeExtensions:)]; import.bordered=NO; import.font=[NSFont systemFontOfSize:12]; import.frame=NSMakeRect(171,16,60,20); import.toolTip=@"Import extensions and supported settings from Chrome"; [root addSubview:import]; previous.nextKeyView=import; import.nextKeyView=manage;
    NSTextField *hint=Label(actions.count?@"Pin extensions in the sidebar.":@"Add extensions from the Chrome Web Store.",12);
    hint.textColor=SLThemeColor(SLSecondaryText); hint.frame=NSMakeRect(16,68+gridHeight,280,18); [root addSubview:hint];
    return root;
}

@implementation SLViewportBackdrop
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirty {
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow=[NSShadow new]; shadow.shadowBlurRadius=11; shadow.shadowOffset=NSMakeSize(0,-3); shadow.shadowColor=[NSColor colorWithWhite:0.14 alpha:0.14]; [shadow set];
    NSBezierPath *surface=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,16,16) xRadius:8 yRadius:8]; [SLThemeColor(SLSurface) setFill]; [surface fill];
    [NSGraphicsContext restoreGraphicsState];
}
@end
