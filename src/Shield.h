#import <Foundation/Foundation.h>

BOOL SLShieldLoad(NSString *path);
void SLShieldConfigure(BOOL enabled, NSArray<NSString *> *pausedHosts);
BOOL SLShieldEnabledForURL(NSString *url);
BOOL SLShieldShouldBlock(NSString *url, NSString *topURL);
NSString *SLShieldCosmeticScript(NSString *topURL, NSString *frameURL);
