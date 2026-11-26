#pragma once
#import <Cocoa/Cocoa.h>
@interface SLExtensionImportPanel : NSWindowController
- (instancetype)initWithChromeRoot:(NSString *)root installed:(NSSet<NSString *> *)installed completion:(void (^)(NSArray<NSDictionary *> *))completion;
- (void)presentForWindow:(NSWindow *)parent;
@end
