#import <Foundation/Foundation.h>

// An empty string represents the native start page; nil rejects an unsafe URL.
NSString *SLResolveAddress(NSString *input);
// External app/Launch Services requests accept web URLs only, never internal pages or scripts.
NSString *SLExternalWebURL(NSString *input);
BOOL SLAllowedNavigation(NSString *url);
BOOL SLTrustedExtensionURL(NSString *url);
BOOL SLIsExtensionsPage(NSString *url);
NSString *SLBrowserURL(NSString *url);
NSString *SLPublicURL(NSString *url);
BOOL SLExtensionDownload(NSString *mimeType, NSString *filename);
NSString *SLNewID(void);
NSDictionary *SLDefaultSession(void);
NSDictionary *SLReadSession(NSString *path);
BOOL SLWriteSession(NSDictionary *state, NSString *path, NSError **error);
