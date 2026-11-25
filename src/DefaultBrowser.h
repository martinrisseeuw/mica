#import <Cocoa/Cocoa.h>
BOOL SLIsDefaultBrowser(void);
void SLRequestDefaultBrowser(void (^completion)(NSError *error));
