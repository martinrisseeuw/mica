#import "Appearance.h"

BOOL SLIsDarkAppearance(NSAppearance *appearance) {
    return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
}
NSColor *SLThemeColor(SLThemeRole role) {
    static NSArray<NSColor *> *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const unsigned light[]={0xFFFFFF,0xF5F5F5,0x232323,0x686868,0x3D4A55,0xE4E4E4,0xE6E7E8,0xECECEC,0xF5F5F5,0x7A8C99,0xCACFD3};
        const unsigned dark[]={0x242424,0x1C1C1E,0xEEEEF0,0xB2B2B8,0xD1DCE4,0x424246,0x3D3D42,0x333337,0x2E2E32,0x8297A8,0x4A4A50};
        NSMutableArray *result=[NSMutableArray array];
        for (NSUInteger i=0;i<sizeof(light)/sizeof(light[0]);i++) {
            unsigned day=light[i], night=dark[i];
            [result addObject:[NSColor colorWithName:[NSString stringWithFormat:@"MicaTheme%lu",(unsigned long)i] dynamicProvider:^NSColor *(NSAppearance *appearance) {
                unsigned hex=SLIsDarkAppearance(appearance)?night:day;
                return [NSColor colorWithSRGBRed:((hex>>16)&255)/255.0 green:((hex>>8)&255)/255.0 blue:(hex&255)/255.0 alpha:1];
            }]];
        }
        colors=result;
    });
    return colors[role];
}

@implementation SLChromeMaterial
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.material=NSVisualEffectMaterialSidebar;
        self.blendingMode=NSVisualEffectBlendingModeBehindWindow;
        self.state=NSVisualEffectStateFollowsWindowActiveState;
        self.clipsToBounds=YES;
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return YES; }
@end

void SLDrawIcon(NSImage *image, NSRect rect, BOOL flipped) {
    if (!image) return;
    if ([image isTemplate]) {
        NSImage *source=image;
        image=[NSImage imageWithSize:rect.size flipped:flipped drawingHandler:^BOOL(NSRect bounds) {
            [source drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:flipped hints:nil];
            [SLThemeColor(SLSecondaryText) setFill]; NSRectFillUsingOperation(bounds,NSCompositingOperationSourceIn);
            return YES;
        }];
    }
    [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:flipped hints:nil];
}
