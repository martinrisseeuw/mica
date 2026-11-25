#import <Foundation/Foundation.h>

// Resolves profile selection without opening Chromium or accessing Keychain.
NSDictionary *SLProfileConfiguration(NSString *support, NSDictionary *environment);
BOOL SLSaveProfileChoice(NSString *support, BOOL keepExisting, NSError **error);
