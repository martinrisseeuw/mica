#import "Profile.h"

NSDictionary *SLProfileConfiguration(NSString *support, NSDictionary *environment) {
    NSString *mica=[support stringByAppendingPathComponent:@"Mica"];
    NSString *legacy=[support stringByAppendingPathComponent:@"Searchlight"];
    NSString *override=environment[@"MICA_PROFILE"];
    if (override.length) return @{@"path":override,@"legacy":@NO,@"needsChoice":@NO};
    override=environment[@"SEARCHLIGHT_PROFILE"];
    if (override.length) return @{@"path":override,@"legacy":@YES,@"needsChoice":@NO};
    NSFileManager *files=NSFileManager.defaultManager;
    BOOL hasMica=[files fileExistsAtPath:mica], hasLegacy=[files fileExistsAtPath:legacy];
    NSData *data=[NSData dataWithContentsOfFile:[mica stringByAppendingPathComponent:@"profile-choice.json"]];
    id choice=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    BOOL keepExisting=[choice isKindOfClass:NSDictionary.class] && [choice[@"source"] isEqual:@"Searchlight"] && hasLegacy;
    return @{@"path":keepExisting?legacy:mica,@"legacy":@(keepExisting),@"needsChoice":@(!hasMica && hasLegacy)};
}

BOOL SLSaveProfileChoice(NSString *support, BOOL keepExisting, NSError **error) {
    NSString *mica=[support stringByAppendingPathComponent:@"Mica"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:mica withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"version":@1,@"source":keepExisting?@"Searchlight":@"Mica"} options:0 error:error];
    return data && [data writeToFile:[mica stringByAppendingPathComponent:@"profile-choice.json"] options:NSDataWritingAtomic error:error];
}
