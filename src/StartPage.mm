#import "StartPage.h"

#import "Appearance.h"

@interface SLStartPage ()
@property NSTextField *address;
@property NSTextField *wordmark;
@property NSArray<NSButton *> *shortcuts;
@property NSArray<NSTextField *> *hints;
@property NSButton *goButton;
@property NSRect searchRect;
@property NSPoint contentOrigin;
@end

@implementation SLStartPage
- (instancetype)initWithFrame:(NSRect)frame target:(id)target {
    if ((self=[super initWithFrame:frame])) {
        self.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        self.clipsToBounds=YES;
        _wordmark=[NSTextField labelWithString:@"Mica"];
        _wordmark.font=[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
        _wordmark.textColor=SLThemeColor(SLAccent); [self addSubview:_wordmark];
        _address=[NSTextField new]; _address.bordered=NO; _address.drawsBackground=NO;
        _address.focusRingType=NSFocusRingTypeNone;
        _address.font=[NSFont systemFontOfSize:16]; _address.textColor=SLThemeColor(SLText);
        _address.placeholderAttributedString=[[NSAttributedString alloc] initWithString:@"Search or enter a URL" attributes:@{NSForegroundColorAttributeName:SLThemeColor(SLSecondaryText),NSFontAttributeName:_address.font}];
        _address.target=target; _address.action=NSSelectorFromString(@"submitAddress:");
        _address.accessibilityLabel=@"Search or enter a URL";
        [self addSubview:_address];
        for (NSNotificationName name in @[NSControlTextDidBeginEditingNotification,NSControlTextDidEndEditingNotification]) {
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(focusChanged:) name:name object:_address];
        }
        _goButton=[NSButton buttonWithTitle:@"↵" target:self action:@selector(submit:)];
        // A real button makes the return affordance useful to mouse users too.
        _goButton.bordered=NO;
        _goButton.font=[NSFont systemFontOfSize:16]; _goButton.contentTintColor=SLThemeColor(SLSecondaryText);
        _goButton.accessibilityLabel=@"Open address or search"; _goButton.toolTip=@"Open address or search";
        [self addSubview:_goButton];
        _shortcuts=@[];
        NSMutableArray *hints=[NSMutableArray array];
        for (NSString *text in @[@"⌘L  Address",@"⌘T  New tab",@"⌥⌘I  DevTools"]) {
            NSTextField *hint=[NSTextField labelWithString:text]; hint.font=[NSFont systemFontOfSize:12];
            hint.textColor=SLThemeColor(SLSecondaryText); [hints addObject:hint]; [self addSubview:hint];
        }
        _hints=hints;
        self.needsLayout=YES;
    }
    return self;
}
- (void)setPinnedItems:(NSArray<NSDictionary *> *)items {
    for (NSButton *button in _shortcuts) [button removeFromSuperview];
    NSMutableArray *buttons=[NSMutableArray array];
    for (NSDictionary *item in items) {
        if (buttons.count==6) break;
        NSButton *button=[NSButton buttonWithTitle:item[@"title"] ?: @"Pinned tab" target:_address.target action:NSSelectorFromString(@"tabClicked:")];
        button.identifier=item[@"id"]; button.bordered=NO;
        button.alignment=NSTextAlignmentLeft; button.font=[NSFont systemFontOfSize:13];
        button.contentTintColor=SLThemeColor(SLSecondaryText); button.lineBreakMode=NSLineBreakByTruncatingTail;
        NSImage *image=[item[@"image"] copy]; image.size=NSMakeSize(16,16); button.image=image;
        button.imagePosition=NSImageLeft; button.imageScaling=NSImageScaleProportionallyDown;
        button.toolTip=item[@"title"]; button.accessibilityLabel=[@"Open pinned tab: " stringByAppendingString:button.title];
        [buttons addObject:button]; [self addSubview:button];
    }
    _shortcuts=buttons; self.needsLayout=YES;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (BOOL)isFlipped { return YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (void)focusChanged:(NSNotification *)notification { self.needsDisplay=YES; }
- (void)submit:(id)sender { [NSApp sendAction:_address.action to:_address.target from:_address]; }
- (void)layout {
    [super layout];
    CGFloat width=MIN(560,MAX(0,self.bounds.size.width-64));
    CGFloat x=floor((self.bounds.size.width-width)/2);
    CGFloat y=floor(MAX(32,MIN(self.bounds.size.height*270.0/836.0,self.bounds.size.height-260)));
    _contentOrigin=NSMakePoint(x,y);
    _wordmark.frame=NSMakeRect(x+44,y+3,120,36);
    _searchRect=NSMakeRect(x,y+68,width,64);
    CGFloat inputHeight=ceil(_address.cell.cellSize.height);
    _address.frame=NSMakeRect(x+54,floor(NSMidY(_searchRect)-inputHeight/2),MAX(0,width-116),inputHeight);
    _goButton.frame=NSMakeRect(x+width-48,y+87,28,26);
    NSUInteger columns=width>=480?3:2;
    CGFloat gap=24, itemWidth=floor((width-(columns-1)*gap)/columns), linkY=y+148;
    for (NSUInteger i=0;i<_shortcuts.count;i++) {
        _shortcuts[i].frame=NSMakeRect(x+(i%columns)*(itemWidth+gap),linkY+(i/columns)*44,itemWidth,36);
    }
    if (_shortcuts.count) linkY+=((_shortcuts.count-1)/columns)*44;
    CGFloat hintWidth=48;
    for (NSTextField *hint in _hints) hintWidth+=ceil(hint.intrinsicContentSize.width);
    CGFloat hintX=floor((self.bounds.size.width-hintWidth)/2);
    for (NSTextField *hint in _hints) {
        CGFloat w=ceil(hint.intrinsicContentSize.width);
        hint.frame=NSMakeRect(hintX,self.bounds.size.height-46,w,18); hintX+=w+24;
        hint.hidden=self.bounds.size.height<linkY+100;
    }
    self.needsDisplay=YES;
}
- (void)mouseDown:(NSEvent *)event {
    if (NSPointInRect([self convertPoint:event.locationInWindow fromView:nil],_searchRect)) {
        [self.window makeFirstResponder:_address]; [_address selectText:nil];
    } else [super mouseDown:event];
}
- (void)drawRect:(NSRect)dirtyRect {
    [SLThemeColor(SLSurface) setFill]; NSRectFill(NSIntersectionRect(dirtyRect,self.bounds));
    // Exact geometry from the Mica new-tab Paper design.
    NSPoint p=_contentOrigin; p.y+=4;
    NSBezierPath *mark=[NSBezierPath bezierPath]; mark.lineWidth=1.5;
    mark.lineCapStyle=NSLineCapStyleRound; mark.lineJoinStyle=NSLineJoinStyleRound;
    [mark moveToPoint:NSMakePoint(p.x+5,p.y+22)]; [mark lineToPoint:NSMakePoint(p.x+16,p.y+28)]; [mark lineToPoint:NSMakePoint(p.x+27,p.y+22)];
    [mark moveToPoint:NSMakePoint(p.x+5,p.y+16)]; [mark lineToPoint:NSMakePoint(p.x+16,p.y+22)]; [mark lineToPoint:NSMakePoint(p.x+27,p.y+16)];
    [mark moveToPoint:NSMakePoint(p.x+5,p.y+10)]; [mark lineToPoint:NSMakePoint(p.x+16,p.y+4)]; [mark lineToPoint:NSMakePoint(p.x+27,p.y+10)]; [mark lineToPoint:NSMakePoint(p.x+16,p.y+16)]; [mark closePath];
    [SLThemeColor(SLAccent) setStroke]; [mark stroke];
    NSBezierPath *border=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(_searchRect,0.5,0.5) xRadius:12 yRadius:12];
    [SLThemeColor(_address.currentEditor?SLFocusBorder:SLBorder) setStroke]; border.lineWidth=1; [border stroke];
    NSPoint icon=NSMakePoint(NSMinX(_searchRect)+20,NSMinY(_searchRect)+22);
    NSBezierPath *glass=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(icon.x+2.75,icon.y+2.75,11.5,11.5)];
    [glass moveToPoint:NSMakePoint(icon.x+13,icon.y+13)]; [glass lineToPoint:NSMakePoint(icon.x+17,icon.y+17)];
    glass.lineWidth=1.5; glass.lineCapStyle=NSLineCapStyleRound; [SLThemeColor(SLSecondaryText) setStroke]; [glass stroke];
    [SLThemeColor(SLChrome) setFill]; [[NSBezierPath bezierPathWithRoundedRect:_goButton.frame xRadius:5 yRadius:5] fill];
}
@end
