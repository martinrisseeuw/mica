#import "ExtensionImport.h"
#include "leveldb/db.h"
#include <cassert>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>

static void JSON(NSString *path, id object) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    assert([[NSJSONSerialization dataWithJSONObject:object options:0 error:nil] writeToFile:path atomically:YES]);
}
static void Seed(NSString *path) {
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    leveldb::Options options; options.create_if_missing=true;
    leveldb::DB *db=nullptr; assert(leveldb::DB::Open(options,path.fileSystemRepresentation,&db).ok());
    assert(db->Put(leveldb::WriteOptions(),"theme","\"dark\"").ok());
    assert(db->Put(leveldb::WriteOptions(),"token","\"source-secret-do-not-import\"").ok());
    assert(db->Put(leveldb::WriteOptions(),"settings","{\"showBadge\":false,\"account\":{\"enabled\":true},\"refreshToken\":\"source-refresh-secret\"}").ok());
    // Exercise compressed SSTables as well as write-ahead log recovery.
    for (int n=0;n<200;n++) assert(db->Put(leveldb::WriteOptions(),"ignored"+std::to_string(n),"\""+std::string(1024,'x')+"\"").ok());
    db->CompactRange(nullptr,nullptr);
    assert(db->Put(leveldb::WriteOptions(),"fontSize","18").ok());
    delete db;
}
static NSDictionary *Bytes(NSString *root) {
    NSMutableDictionary *files=[NSMutableDictionary dictionary];
    for (NSString *path in [NSFileManager.defaultManager enumeratorAtPath:root]) {
        NSData *data=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:path]];
        if (data) files[path]=data;
    }
    return files;
}
int main(int argc,char **argv) { @autoreleasepool {
    if (argc==3 && std::string(argv[1])=="--seed") { Seed([NSString stringWithUTF8String:argv[2]]); return 0; }
    NSString *root=[[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] stringByResolvingSymlinksInPath];
    NSString *identifier=@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    NSString *profile=[root stringByAppendingPathComponent:@"Default"];
    NSString *database=[[profile stringByAppendingPathComponent:@"Local Extension Settings"] stringByAppendingPathComponent:identifier];
    Seed(database);
    NSDictionary *before=Bytes(root); NSError *error=nil;
    NSDictionary *preferences=SLReadExtensionPreferences(database,&error);
    assert(!error && [preferences[@"theme"] isEqual:@"dark"] && [preferences[@"fontSize"] isEqual:@18]);
    assert([preferences[@"settings"] isEqual:@{@"showBadge":@NO}]);
    assert(preferences.count==3 && [before isEqual:Bytes(root)]);
    NSDictionary *dangerous=@{@"token":@"secret",@"theme":@"opaque-token",@"isLoggedIn":@YES,@"account":@{@"theme":@"dark"},@"settings":@{@"theme":@"light",@"refreshToken":@"secret",@"options":@{@"brightness":@120,@"cookie":@"secret"}},@"fontSize":@999999,@"enabled":@"secret",@"__proto__":@{@"enabled":@YES}};
    NSDictionary *safe=SLImportablePreferences(dangerous);
    assert(([safe isEqual:@{@"settings":@{@"theme":@"light",@"options":@{@"brightness":@120}}}]));
    assert(SLPreferenceCount(safe)==2 && SLImportablePreferences(@[]).count==0);
    assert(SLImportablePreferences(@{@"fontSize":@YES,@"mode":@YES,@"theme":@[@"dark"]}).count==0);
    assert(SLValidExtensionID(identifier) && !SLValidExtensionID(@"../bad") && !SLValidExtensionID(@123));
    NSString *link=[root stringByAppendingPathComponent:@"link"];
    assert([NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:database error:nil]);
    assert(!SLReadExtensionPreferences(link,&error));
    [NSFileManager.defaultManager removeItemAtPath:link error:nil];
    NSString *relative=[identifier stringByAppendingPathComponent:@"1.0_0"];
    NSDictionary *entry=@{@"path":relative,@"from_webstore":@YES};
    JSON([profile stringByAppendingPathComponent:@"Preferences"],@{@"profile":@{@"name":@"Work"},@"extensions":@{@"settings":@{identifier:entry}}});
    JSON([[[profile stringByAppendingPathComponent:@"Extensions"] stringByAppendingPathComponent:relative] stringByAppendingPathComponent:@"manifest.json"],@{@"manifest_version":@3,@"name":@"__MSG_name__",@"default_locale":@"en",@"version":@"1.0"});
    JSON([[[profile stringByAppendingPathComponent:@"Extensions"] stringByAppendingPathComponent:relative] stringByAppendingPathComponent:@"_locales/en/messages.json"],@{@"name":@{@"message":@"Fixture"}});
    JSON([root stringByAppendingPathComponent:@"Local State"],@{@"profile":@{@"info_cache":@{@"Default":@{@"name":@"Work"}}}});
    assert(SLChromeProfiles(root,nil).count==1);
    NSArray *extensions=SLChromeExtensions(profile,[NSSet set],nil);
    assert(extensions.count==1 && [extensions[0][@"name"] isEqual:@"Fixture"] && [extensions[0][@"count"] isEqual:@3]);
    NSArray *duplicates=SLChromeExtensions(profile,[NSSet setWithObject:identifier],nil);
    assert([duplicates[0][@"installed"] boolValue] && [duplicates[0][@"settings"] count]==0);
    JSON([profile stringByAppendingPathComponent:@"Secure Preferences"],@{@"extensions":@{@"settings":@{identifier:@{@"path":relative,@"from_webstore":@NO}}}});
    NSArray *nonstore=SLChromeExtensions(profile,[NSSet set],nil);
    assert(nonstore.count==1 && ![nonstore[0][@"supported"] boolValue] && [nonstore[0][@"settings"] count]==0);
    JSON([profile stringByAppendingPathComponent:@"Secure Preferences"],@{@"extensions":@{@"settings":@{identifier:@{@"path":@"../../outside",@"from_webstore":@YES}}}});
    assert(SLChromeExtensions(profile,[NSSet set],nil).count==0);
    [NSFileManager.defaultManager removeItemAtPath:[profile stringByAppendingPathComponent:@"Secure Preferences"] error:nil];
    // A live Chrome writer must block the snapshot without changing its files.
    int ready[2]; assert(pipe(ready)==0); pid_t child=fork(); assert(child>=0);
    if (!child) {
        close(ready[0]); int fd=open([database stringByAppendingPathComponent:@"LOCK"].fileSystemRepresentation,O_RDWR);
        struct flock guard={}; guard.l_type=F_WRLCK; guard.l_whence=SEEK_SET;
        assert(fd>=0 && fcntl(fd,F_SETLK,&guard)==0); assert(write(ready[1],"x",1)==1); sleep(2); _exit(0);
    }
    close(ready[1]); char signal; assert(read(ready[0],&signal,1)==1); close(ready[0]);
    error=nil; assert(!SLReadExtensionPreferences(database,&error) && [error.localizedDescription containsString:@"Quit Chrome"]);
    int status; waitpid(child,&status,0); assert(status==0);
    // A corrupt snapshot fails closed; never repair or replace source files.
    NSString *broken=[root stringByAppendingPathComponent:@"broken"];
    [NSFileManager.defaultManager createDirectoryAtPath:broken withIntermediateDirectories:YES attributes:nil error:nil];
    [NSData.data writeToFile:[broken stringByAppendingPathComponent:@"LOCK"] atomically:YES];
    [@"MANIFEST-000001\n" writeToFile:[broken stringByAppendingPathComponent:@"CURRENT"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"corrupt" writeToFile:[broken stringByAppendingPathComponent:@"MANIFEST-000001"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    before=Bytes(broken); error=nil;
    assert(!SLReadExtensionPreferences(broken,&error) && error && [before isEqual:Bytes(broken)]);
    NSString *queue=[root stringByAppendingPathComponent:@"imports.json"];
    NSDictionary *job=@{@"id":identifier,@"space":@"space-1",@"name":@"Fixture",@"state":@"applying",@"settings":@{@"local":dangerous,@"session":@{@"theme":@"dark"}}};
    assert(SLSaveExtensionImports(@[job],queue,nil));
    NSArray *restored=SLReadExtensionImports(queue); assert(restored.count==1 && [restored[0][@"state"] isEqual:@"failed"]);
    assert([restored[0][@"settings"][@"local"] isEqual:safe] && !restored[0][@"settings"][@"session"]);
    NSString *serialized=[NSString stringWithContentsOfFile:queue encoding:NSUTF8StringEncoding error:nil];
    assert(![serialized containsString:@"secret"] && ![serialized containsString:@"refreshToken"]);
    assert([NSFileManager.defaultManager attributesOfItemAtPath:queue error:nil].filePosixPermissions==0600);
    for (NSString *state in @[@"ready",@"queued",@"done"]) {
        NSMutableDictionary *pending=[job mutableCopy]; pending[@"state"]=state;
        assert(SLSaveExtensionImports(@[pending],queue,nil));
        NSDictionary *record=SLReadExtensionImports(queue).firstObject;
        assert([record[@"state"] isEqual:([state isEqual:@"queued"]?@"ready":state)] && [record[@"settings"][@"local"] isEqual:safe]);
    }
    assert(!SLSaveExtensionImports(@[@{@"id":@"invalid"}],queue,nil));
    assert(!SLExtensionSettingsScript(@"invalid",@{}));
    NSString *script=SLExtensionSettingsScript(identifier,@{@"local":dangerous});
    assert([script containsString:@"chrome.runtime.id"] && ![script containsString:@"secret"]);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    puts("Extension import tests passed: storage, filtering, profiles, locks, queue and source preservation.");
} }
