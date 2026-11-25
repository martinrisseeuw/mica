#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSUInteger, SLThemeRole) {
    SLSurface, SLChrome, SLText, SLSecondaryText, SLAccent, SLBorder,
    SLSelection, SLHover, SLTile, SLFocusBorder, SLPopoverBorder
};
NSColor *SLThemeColor(SLThemeRole role);
BOOL SLIsDarkAppearance(NSAppearance *appearance);

@interface SLChromeMaterial : NSVisualEffectView
@end
void SLDrawIcon(NSImage *image, NSRect rect, BOOL flipped);
