#import <Cocoa/Cocoa.h>

@protocol SLExtensionActions <NSObject>
- (void)openExtensionButton:(NSButton *)sender;
- (void)toggleExtensionPin:(NSButton *)sender;
- (void)showExtensions:(id)sender;
- (void)browseExtensions:(id)sender;
- (void)importChromeExtensions:(id)sender;
- (void)hideExtensionMenu;
@end

@interface SLExtensionPanel : NSPanel
@property(nonatomic, weak) id<SLExtensionActions> actionTarget;
@end

NSView *SLExtensionGrid(NSArray<NSDictionary *> *actions, NSArray<NSString *> *pins, id<SLExtensionActions> target);
NSButton *SLExtensionControl(NSView *root, NSString *identifier, SEL action);
// Bits: top left, top right, bottom left, bottom right.
void SLClipViewport(NSView *view, NSUInteger corners);

@interface SLViewportBackdrop : NSView
@end
