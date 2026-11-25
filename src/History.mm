#import "History.h"
#include <cmath>

NSString *SLHistoryURL(NSString *url) {
    if (![url isKindOfClass:NSString.class] || url.length>4096) return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithString:url];
    if (![@[@"http",@"https"] containsObject:parts.scheme.lowercaseString] || !parts.host.length) return nil;
    parts.user=nil; parts.password=nil;
    if (!parts.path.length) parts.path=@"/";
    return parts.URL.absoluteString;
}
static NSString *WithoutScheme(NSString *url) {
    NSRange scheme=[url rangeOfString:@"://"];
    return scheme.location==NSNotFound ? url : [url substringFromIndex:NSMaxRange(scheme)];
}
NSString *SLCompletion(NSString *query, NSString *url) {
    if (!query.length) return nil;
    NSString *value=[query containsString:@"://"] ? url : WithoutScheme(url);
    if (![query.lowercaseString hasPrefix:@"www."] && [value hasPrefix:@"www."]) value=[value substringFromIndex:4];
    return [value.lowercaseString hasPrefix:query.lowercaseString] && value.length>query.length ? value : nil;
}
@implementation SLHistory {
    NSString *_path;
    NSMutableArray<NSMutableDictionary *> *_records;
    BOOL _dirty;
}
- (instancetype)initWithPath:(NSString *)path {
    if ((self=[super init])) {
        _path=path; _records=[NSMutableArray array];
        NSData *data=[NSData dataWithContentsOfFile:path];
        id raw=data.length && data.length<16*1024*1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSMutableSet *seen=[NSMutableSet set];
        if ([raw isKindOfClass:NSArray.class]) for (id item in raw) {
            if (_records.count>=2000) break;
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString *url=SLHistoryURL(item[@"url"]);
            if (!url || [seen containsObject:url] || ![item[@"title"] isKindOfClass:NSString.class] || ![item[@"lastVisit"] isKindOfClass:NSNumber.class] || ![item[@"visits"] isKindOfClass:NSNumber.class]) continue;
            double time=[item[@"lastVisit"] doubleValue];
            if (!std::isfinite(time) || time<0) continue;
            [seen addObject:url]; NSString *title=item[@"title"];
            [_records addObject:[@{@"url":url,@"title":[title substringToIndex:MIN(title.length,500UL)],@"lastVisit":@(MIN(time,NSDate.date.timeIntervalSince1970)),@"visits":@(MAX(1,MIN(100000,[item[@"visits"] integerValue])))} mutableCopy]];
        }
    }
    return self;
}
- (NSArray *)entries { return [_records copy]; }
- (void)visit:(NSString *)input title:(NSString *)title {
    NSString *url=SLHistoryURL(input); if (!url) return;
    NSMutableDictionary *entry=nil;
    for (NSMutableDictionary *candidate in _records) if ([candidate[@"url"] isEqual:url]) { entry=candidate; break; }
    if (entry) [_records removeObject:entry]; else entry=[@{@"url":url,@"visits":@0} mutableCopy];
    NSString *label=title.length?title:url;
    entry[@"title"]=[label substringToIndex:MIN(label.length,500UL)];
    entry[@"visits"]=@(MIN(100000,[entry[@"visits"] integerValue]+1)); entry[@"lastVisit"]=@(NSDate.date.timeIntervalSince1970);
    [_records insertObject:entry atIndex:0];
    if (_records.count>2000) [_records removeLastObject]; _dirty=YES;
}
- (void)updateTitle:(NSString *)title forURL:(NSString *)input {
    if (!title.length) return; NSString *url=SLHistoryURL(input);
    for (NSMutableDictionary *entry in _records) if ([entry[@"url"] isEqual:url]) {
        NSString *label=[title substringToIndex:MIN(title.length,500UL)];
        if (![entry[@"title"] isEqual:label]) { entry[@"title"]=label; _dirty=YES; } break;
    }
}
- (NSArray *)suggestions:(NSString *)input tabs:(NSArray *)tabs {
    NSString *query=[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSMutableDictionary *unique=[NSMutableDictionary dictionary];
    for (NSDictionary *entry in _records) unique[entry[@"url"]]=[entry mutableCopy];
    for (NSDictionary *tab in tabs) {
        NSString *url=SLHistoryURL(tab[@"url"]); if (!url) continue;
        NSMutableDictionary *entry=unique[url];
        if (!entry) { entry=[@{@"url":url,@"title":tab[@"title"] ?: url,@"visits":@0,@"lastVisit":@0} mutableCopy]; unique[url]=entry; }
        if (!entry[@"tabID"]) entry[@"tabID"]=tab[@"id"];
    }
    NSMutableArray *matches=[NSMutableArray array];
    for (NSMutableDictionary *entry in unique.allValues) {
        NSString *url=[entry[@"url"] lowercaseString], *title=[entry[@"title"] lowercaseString];
        if (query.length && ![url containsString:query] && ![title containsString:query]) continue;
        NSString *bare=WithoutScheme(url); if ([bare hasPrefix:@"www."]) bare=[bare substringFromIndex:4];
        entry[@"prefix"]=@(query.length && ([bare hasPrefix:query] || [url hasPrefix:query]));
        [matches addObject:entry];
    }
    [matches sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        for (NSString *key in @[@"prefix",@"visits",@"lastVisit"]) {
            NSComparisonResult order=[b[key] compare:a[key]]; if (order!=NSOrderedSame) return order;
        }
        return [a[@"url"] compare:b[@"url"]];
    }];
    return [matches subarrayWithRange:NSMakeRange(0,MIN(matches.count,5UL))];
}
- (BOOL)save {
    if (!_dirty) return YES;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:_records options:0 error:nil];
    if (![data writeToFile:_path options:NSDataWritingAtomic error:nil]) return NO;
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:_path error:nil];
    _dirty=NO; return YES;
}
- (void)clear { [_records removeAllObjects]; _dirty=YES; [self save]; }
@end
