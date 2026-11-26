#pragma once
#import <Foundation/Foundation.h>

BOOL SLValidExtensionID(id value);
NSArray<NSDictionary *> *SLChromeProfiles(NSString *root, NSError **error);
NSArray<NSDictionary *> *SLChromeExtensions(NSString *profile, NSSet<NSString *> *installed, NSError **error);
// Only explicitly recognized preference names, types and bounded values pass.
// Never a denylist of token names: unknown values are excluded by default.
NSDictionary *SLImportablePreferences(id input);
NSUInteger SLPreferenceCount(NSDictionary *values);
NSDictionary *SLReadExtensionPreferences(NSString *directory, NSError **error);
NSString *SLExtensionSettingsScript(NSString *identifier, NSDictionary *settings);
BOOL SLSaveExtensionImports(NSArray<NSDictionary *> *jobs, NSString *path, NSError **error);
NSArray<NSMutableDictionary *> *SLReadExtensionImports(NSString *path);
