#import "ExtensionImport.h"
#include "leveldb/db.h"
#include "leveldb/env.h"
#include "helpers/memenv/memenv.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <memory>
#include <cmath>

static void Failure(NSError **error, NSString *message) {
    if (error) *error=[NSError errorWithDomain:@"MicaExtensionImport" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL Matches(NSString *value, NSString *pattern) {
    return [value isKindOfClass:NSString.class] && [value rangeOfString:pattern options:NSRegularExpressionSearch].location!=NSNotFound;
}
BOOL SLValidExtensionID(id value) { return Matches(value,@"^[a-p]{32}$"); }
static BOOL SafePath(NSString *path) {
    return path.isAbsolutePath && [path.stringByStandardizingPath isEqual:path.stringByResolvingSymlinksInPath];
}
static NSData *ReadFile(NSString *path, NSUInteger limit) {
    if (!SafePath(path)) return nil;
    int file=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    if (file<0) return nil;
    struct stat info;
    if (fstat(file,&info) || !S_ISREG(info.st_mode) || info.st_size<0 || (uint64_t)info.st_size>limit) { close(file); return nil; }
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)info.st_size];
    size_t offset=0;
    while (offset<data.length) {
        ssize_t count=read(file,(char *)data.mutableBytes+offset,data.length-offset);
        if (count<=0) { close(file); return nil; }
        offset+=(size_t)count;
    }
    close(file); return data;
}
static NSDictionary *ReadJSON(NSString *path) {
    NSData *data=ReadFile(path,8*1024*1024);
    id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    return [value isKindOfClass:NSDictionary.class]?value:nil;
}
static NSDictionary *Dictionary(id value) { return [value isKindOfClass:NSDictionary.class]?value:@{}; }
static NSString *Text(id value, NSString *fallback) { return [value isKindOfClass:NSString.class] && [value length]<=200?value:fallback; }

NSArray<NSDictionary *> *SLChromeProfiles(NSString *root, NSError **error) {
    if (!SafePath(root)) { Failure(error,@"Choose a Chrome data folder without symbolic links."); return nil; }
    NSArray *children=[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:error];
    if (!children) return nil;
    NSDictionary *cache=Dictionary(Dictionary(ReadJSON([root stringByAppendingPathComponent:@"Local State"])[@"profile"])[@"info_cache"]);
    NSMutableArray *profiles=[NSMutableArray array];
    for (NSString *name in [children sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if (![name isEqual:@"Default"] && !Matches(name,@"^Profile [0-9]+$")) continue;
        NSString *path=[root stringByAppendingPathComponent:name];
        if (!SafePath(path)) continue;
        NSDictionary *prefs=ReadJSON([path stringByAppendingPathComponent:@"Preferences"]);
        if (!prefs) continue;
        NSString *label=Text(Dictionary(cache[name])[@"name"],Text(Dictionary(prefs[@"profile"])[@"name"],name));
        [profiles addObject:@{@"path":path,@"name":[NSString stringWithFormat:@"%@ (%@)",label,name]}];
    }
    return profiles;
}

static id Preference(NSString *key, id value, NSUInteger depth) {
    if (depth>4 || ![key isKindOfClass:NSString.class]) return nil;
    NSString *name=[[key stringByReplacingOccurrencesOfString:@"_" withString:@""] lowercaseString];
    NSSet *containers=[NSSet setWithArray:@[@"settings",@"preferences",@"options",@"config",@"theme",@"appearance"]];
    if ([containers containsObject:name] && [value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *clean=[NSMutableDictionary dictionary];
        if ([value count]>1000) return nil;
        for (NSString *child in value) { id next=Preference(child,value[child],depth+1); if (next) clean[child]=next; }
        return clean.count?clean:nil;
    }
    NSDictionary *enums=@{
        @"theme":@[@"light",@"dark",@"system",@"auto",@"default"],
        @"uitheme":@[@"light",@"dark",@"system",@"auto",@"default"],
        @"colorscheme":@[@"light",@"dark",@"system",@"auto"],
        @"appearance":@[@"light",@"dark",@"system",@"auto"],
        @"position":@[@"left",@"right",@"top",@"bottom"],
        @"engine":@[@"dynamicTheme",@"cssFilter",@"svgFilter",@"staticTheme"]};
    if ([value isKindOfClass:NSString.class] && [enums[name] containsObject:value]) return value;
    NSSet *booleans=[NSSet setWithArray:@[@"enabled",@"darkmode",@"showbadge",@"shownotifications",@"showtooltips",@"compactmode",@"animations",@"reducedmotion",@"usefont",@"enableforpdf",@"enabledforpdf",@"detectdarktheme",@"previewnewdesign",@"fetchnews"]];
    if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return [booleans containsObject:name]?value:nil;
    NSDictionary *ranges=@{@"fontsize":@[@6,@72],@"zoom":@[@0.25,@5],@"brightness":@[@0,@200],@"contrast":@[@0,@200],@"sepia":@[@0,@100],@"grayscale":@[@0,@100],@"textstroke":@[@0,@1],@"mode":@[@0,@1]};
    NSArray *range=ranges[name];
    if (range && [value isKindOfClass:NSNumber.class] && std::isfinite([value doubleValue]) && [value doubleValue]>=[range[0] doubleValue] && [value doubleValue]<=[range[1] doubleValue]) return value;
    return nil;
}
NSDictionary *SLImportablePreferences(id input) {
    if (![input isKindOfClass:NSDictionary.class] || [input count]>1000) return @{};
    NSMutableDictionary *clean=[NSMutableDictionary dictionary];
    for (NSString *key in input) { id value=Preference(key,input[key],0); if (value) clean[key]=value; }
    return clean;
}
NSUInteger SLPreferenceCount(NSDictionary *values) {
    NSUInteger count=0;
    for (id value in values.allValues) count+=[value isKindOfClass:NSDictionary.class]?SLPreferenceCount(value):1;
    return count;
}

NSDictionary *SLReadExtensionPreferences(NSString *directory, NSError **error) {
    if (!SafePath(directory)) { Failure(error,@"Settings contain symbolic links and were skipped."); return nil; }
    if (![NSFileManager.defaultManager fileExistsAtPath:directory]) return @{};
    // Read a bounded snapshot into RAM. LevelDB recovery never touches Chrome's
    // files, and unfiltered source data is never staged on disk in Mica.
    int lock=open([directory stringByAppendingPathComponent:@"LOCK"].fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    struct flock guard={}; guard.l_type=F_RDLCK; guard.l_whence=SEEK_SET;
    if (lock<0 || fcntl(lock,F_SETLK,&guard)<0) { if(lock>=0) close(lock); Failure(error,@"Quit Chrome before importing settings."); return nil; }
    auto env=std::unique_ptr<leveldb::Env>(leveldb::NewMemEnv(leveldb::Env::Default()));
    env->CreateDir("/settings");
    NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:error];
    NSUInteger total=0; BOOL valid=names!=nil;
    for (NSString *name in names) {
        if (![name isEqual:@"CURRENT"] && !Matches(name,@"^MANIFEST-[0-9]+$") && !Matches(name,@"^[0-9]+\\.(log|ldb|sst)$")) continue;
        NSData *data=ReadFile([directory stringByAppendingPathComponent:name],32*1024*1024);
        total+=data.length;
        if (!data || total>32*1024*1024) { valid=NO; break; }
        leveldb::WritableFile *raw=nullptr;
        auto status=env->NewWritableFile(std::string("/settings/")+name.UTF8String,&raw);
        std::unique_ptr<leveldb::WritableFile> file(raw);
        if (!status.ok() || !file->Append(leveldb::Slice((const char *)data.bytes,data.length)).ok() || !file->Close().ok()) { valid=NO; break; }
    }
    guard.l_type=F_UNLCK; fcntl(lock,F_SETLK,&guard); close(lock);
    if (!valid) { Failure(error,@"Settings are unreadable or exceed the 32 MB import limit."); return nil; }
    leveldb::Options options; options.env=env.get(); options.paranoid_checks=true;
    leveldb::DB *raw=nullptr;
    auto status=leveldb::DB::Open(options,"/settings",&raw);
    std::unique_ptr<leveldb::DB> db(raw);
    if (!status.ok()) { Failure(error,@"Chrome’s settings database could not be read."); return nil; }
    leveldb::ReadOptions read; read.verify_checksums=true;
    auto iterator=std::unique_ptr<leveldb::Iterator>(db->NewIterator(read));
    NSMutableDictionary *clean=[NSMutableDictionary dictionary]; NSUInteger count=0;
    for (iterator->SeekToFirst(); iterator->Valid(); iterator->Next()) {
        if (++count>10000) { Failure(error,@"This extension has too many settings to import."); return nil; }
        if (iterator->key().size()>128 || iterator->value().size()>1024*1024) continue;
        NSString *key=[[NSString alloc] initWithBytes:iterator->key().data() length:iterator->key().size() encoding:NSUTF8StringEncoding];
        NSData *data=[NSData dataWithBytes:iterator->value().data() length:iterator->value().size()];
        id value=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
        id accepted=key?Preference(key,value,0):nil; if (accepted) clean[key]=accepted;
    }
    if (!iterator->status().ok()) { Failure(error,@"Chrome’s settings database is damaged; settings were skipped."); return nil; }
    return clean;
}

NSArray<NSDictionary *> *SLChromeExtensions(NSString *profile, NSSet<NSString *> *installed, NSError **error) {
    if (!SafePath(profile)) { Failure(error,@"The selected Chrome profile is unavailable."); return nil; }
    NSDictionary *prefs=ReadJSON([profile stringByAppendingPathComponent:@"Preferences"]);
    if (!prefs) { Failure(error,@"Chrome’s profile preferences could not be read."); return nil; }
    NSMutableDictionary *entries=[Dictionary(Dictionary(prefs[@"extensions"])[@"settings"]) mutableCopy];
    NSDictionary *secure=ReadJSON([profile stringByAppendingPathComponent:@"Secure Preferences"]);
    [entries addEntriesFromDictionary:Dictionary(Dictionary(secure[@"extensions"])[@"settings"])];
    NSMutableArray *extensions=[NSMutableArray array];
    for (NSString *identifier in entries) {
        if (!SLValidExtensionID(identifier)) continue;
        NSDictionary *entry=Dictionary(entries[identifier]);
        NSString *relative=entry[@"path"];
        if (![relative isKindOfClass:NSString.class] || relative.isAbsolutePath || [relative.pathComponents containsObject:@".."] || ![relative.pathComponents.firstObject isEqual:identifier]) continue;
        NSString *path=[[profile stringByAppendingPathComponent:@"Extensions"] stringByAppendingPathComponent:relative];
        NSDictionary *manifest=ReadJSON([path stringByAppendingPathComponent:@"manifest.json"]);
        if (!manifest || manifest[@"theme"] || manifest[@"app"]) continue;
        NSString *name=Text(manifest[@"name"],identifier);
        if ([name hasPrefix:@"__MSG_"] && [name hasSuffix:@"__"] && name.length>8) {
            NSString *locale=manifest[@"default_locale"];
            if (Matches(locale,@"^[A-Za-z_@-]+$")) {
                NSDictionary *messages=ReadJSON([path stringByAppendingPathComponent:[NSString stringWithFormat:@"_locales/%@/messages.json",locale]]);
                NSString *key=[name substringWithRange:NSMakeRange(6,name.length-8)];
                name=Text(Dictionary(messages[key])[@"message"],identifier);
            }
        }
        BOOL webstore=[entry[@"from_webstore"] isKindOfClass:NSNumber.class] && [entry[@"from_webstore"] boolValue];
        BOOL duplicate=[installed containsObject:identifier];
        NSMutableDictionary *settings=[NSMutableDictionary dictionary]; NSMutableArray *warnings=[NSMutableArray array];
        if (webstore && !duplicate) for (NSString *area in @[@"local",@"sync"]) {
            NSString *folder=[area isEqual:@"local"]?@"Local Extension Settings":@"Sync Extension Settings";
            NSError *issue=nil;
            NSDictionary *values=SLReadExtensionPreferences([[profile stringByAppendingPathComponent:folder] stringByAppendingPathComponent:identifier],&issue);
            if (values.count) settings[area]=values;
            if (issue) [warnings addObject:issue.localizedDescription];
        }
        NSUInteger count=SLPreferenceCount(settings[@"local"])+SLPreferenceCount(settings[@"sync"]);
        [extensions addObject:@{@"id":identifier,@"name":name,@"version":Text(manifest[@"version"],@""),@"settings":settings,@"count":@(count),@"installed":@(duplicate),@"supported":@(webstore),@"warning":[warnings componentsJoinedByString:@" "]}];
    }
    return [extensions sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
}

NSString *SLExtensionSettingsScript(NSString *identifier, NSDictionary *settings) {
    if (!SLValidExtensionID(identifier)) return nil;
    NSDictionary *clean=@{@"local":SLImportablePreferences(settings[@"local"]),@"sync":SLImportablePreferences(settings[@"sync"])};
    NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:clean options:0 error:nil] encoding:NSUTF8StringEncoding];
    // Existing destination values stay in the renderer, including any newly
    // authenticated account. Only recognized source preferences enter here.
    return [NSString stringWithFormat:@"(async()=>{if(location.origin!=='chrome-extension://%@'||chrome.runtime.id!=='%@'||!chrome.storage)throw Error('Extension storage unavailable');const incoming=%@;const object=v=>v&&typeof v==='object'&&!Array.isArray(v);const merge=(old,next)=>{const result=object(old)?{...old}:{};for(const [k,v]of Object.entries(next))result[k]=object(v)?merge(result[k],v):v;return result;};for(const area of ['local','sync']){const next=incoming[area];if(!Object.keys(next).length)continue;const old=await chrome.storage[area].get(Object.keys(next));await chrome.storage[area].set(merge(old,next));}return true;})()",identifier,identifier,json];
}

static NSMutableDictionary *CleanJob(id input) {
    NSDictionary *job=Dictionary(input);
    if (!SLValidExtensionID(job[@"id"]) || !Matches(job[@"space"],@"^[A-Za-z0-9-]{1,64}$")) return nil;
    NSString *state=job[@"state"];
    if (![@[@"waiting",@"applying",@"done",@"failed"] containsObject:state]) return nil;
    NSDictionary *settings=Dictionary(job[@"settings"]);
    return [@{@"id":job[@"id"],@"space":job[@"space"],@"name":Text(job[@"name"],job[@"id"]),@"state":state,@"settings":@{@"local":SLImportablePreferences(settings[@"local"]),@"sync":SLImportablePreferences(settings[@"sync"])}} mutableCopy];
}
BOOL SLSaveExtensionImports(NSArray<NSDictionary *> *jobs, NSString *path, NSError **error) {
    if (!SafePath(path) || jobs.count>200) { Failure(error,@"The import queue cannot be saved."); return NO; }
    NSMutableArray *clean=[NSMutableArray array];
    for (id input in jobs) { NSDictionary *job=CleanJob(input); if (!job) { Failure(error,@"Invalid extension import."); return NO; } [clean addObject:job]; }
    NSData *data=[NSJSONSerialization dataWithJSONObject:clean options:0 error:error];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error] && [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:error];
}
NSArray<NSMutableDictionary *> *SLReadExtensionImports(NSString *path) {
    NSData *data=ReadFile(path,2*1024*1024);
    id raw=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    NSMutableArray *jobs=[NSMutableArray array];
    if (![raw isKindOfClass:NSArray.class] || [raw count]>200) return jobs;
    for (id input in raw) { NSMutableDictionary *job=CleanJob(input); if (job) { if ([job[@"state"] isEqual:@"applying"]) job[@"state"]=@"failed"; [jobs addObject:job]; } }
    return jobs;
}
