#import "Model.h"

NSString *SLExternalWebURL(NSString *input) {
    if (![input isKindOfClass:NSString.class] || !input.length || [input rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithString:input];
    if (![@[@"http",@"https"] containsObject:parts.scheme.lowercaseString ?: @""] || !parts.host.length) return nil;
    return parts.URL.absoluteString;
}
NSString *SLNewID(void) { return NSUUID.UUID.UUIDString.lowercaseString; }
BOOL SLIsExtensionsPage(NSString *url) {
    NSURLComponents *parts=[NSURLComponents componentsWithString:url];
    return !parts.user && !parts.password && !parts.port && [parts.host.lowercaseString isEqual:@"extensions"] && [@[@"mica",@"searchlight"] containsObject:parts.scheme.lowercaseString ?: @""];
}
NSString *SLBrowserURL(NSString *url) {
    if (!SLIsExtensionsPage(url)) return url;
    NSURLComponents *parts=[NSURLComponents componentsWithString:url]; parts.scheme=@"chrome"; parts.host=@"extensions";
    if (!parts.path.length) parts.path=@"/";
    return parts.string;
}
NSString *SLPublicURL(NSString *url) {
    NSURLComponents *parts=[NSURLComponents componentsWithString:url];
    BOOL manager=[parts.scheme.lowercaseString isEqual:@"chrome"] && [parts.host.lowercaseString isEqual:@"extensions"] && !parts.user && !parts.password && !parts.port;
    if (!manager && !SLIsExtensionsPage(url)) return url;
    parts.scheme=@"mica"; parts.host=@"extensions"; if (!parts.path.length) parts.path=@"/";
    return parts.string;
}
BOOL SLExtensionDownload(NSString *mimeType, NSString *filename) {
    NSString *mime=[[mimeType componentsSeparatedByString:@";"].firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    return [mime isEqual:@"application/x-chrome-extension"] || [filename.pathExtension.lowercaseString isEqual:@"crx"];
}
BOOL SLTrustedExtensionURL(NSString *url) {
    NSURLComponents *parts=[NSURLComponents componentsWithString:url];
    if (parts.user || parts.password || parts.port) return NO;
    if ([parts.scheme isEqual:@"chrome"] && [parts.host isEqual:@"extensions"]) return YES;
    if (![parts.scheme isEqual:@"chrome-extension"] || parts.host.length!=32) return NO;
    return [parts.host rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnop"] invertedSet]].location==NSNotFound;
}
BOOL SLAllowedNavigation(NSString *url) {
    NSString *scheme = [NSURLComponents componentsWithString:url].scheme.lowercaseString;
    return [scheme isEqual:@"http"] || [scheme isEqual:@"https"] || [url isEqual:@"about:blank"];
}
NSString *SLResolveAddress(NSString *input) {
    if (![input isKindOfClass:NSString.class]) return nil;
    NSString *value = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (SLIsExtensionsPage(SLPublicURL(value))) return SLPublicURL(value);
    if (!value.length || [value isEqual:@"mica://newtab"] || [value isEqual:@"searchlight://newtab"]) return @"";
    if ([value isEqual:@"about:blank"]) return value;
    NSRegularExpression *local = [NSRegularExpression regularExpressionWithPattern:@"^(localhost|[a-zA-Z0-9_-]+|\\[[0-9a-fA-F:]+\\]):[0-9]+(?:[/?#].*)?$" options:0 error:nil];
    BOOL hostPort = [local firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] != nil;
    NSRegularExpression *scheme = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z][a-zA-Z0-9+.-]*:" options:0 error:nil];
    if (!hostPort && [scheme firstMatchInString:value options:0 range:NSMakeRange(0, value.length)]) {
        if (!SLAllowedNavigation(value)) return nil;
        NSURLComponents *parts = [NSURLComponents componentsWithString:value];
        return parts.host.length ? parts.URL.absoluteString : nil;
    }
    BOOL noSpaces = [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound;
    NSString *host = [[value componentsSeparatedByString:@"/"] firstObject];
    BOOL looksLocal = [host isEqual:@"localhost"] || [host hasPrefix:@"localhost:"] || [host hasPrefix:@"127."] || [host hasPrefix:@"0.0.0.0"] || [host hasPrefix:@"[::1]"] || hostPort;
    if (noSpaces && (looksLocal || [host containsString:@"."])) {
        NSString *url = [NSString stringWithFormat:@"%@://%@", looksLocal ? @"http" : @"https", value];
        NSURLComponents *parts = [NSURLComponents componentsWithString:url];
        if (parts.host.length) return parts.URL.absoluteString;
    }
    NSURLComponents *search = [NSURLComponents componentsWithString:@"https://duckduckgo.com/"];
    search.queryItems = @[[NSURLQueryItem queryItemWithName:@"q" value:value]];
    return search.URL.absoluteString;
}
NSDictionary *SLDefaultSession(void) {
    NSString *space = SLNewID(), *tab = SLNewID();
    return @{@"version": @1, @"activeSpace": space, @"sidebarVisible": @YES, @"adblockEnabled": @YES, @"adblockPausedHosts": @[], @"devToolsPosition": @"bottom",
      @"spaces": @[@{@"id": space, @"name": @"Development", @"activeTab": tab, @"folders":@[],
        @"tabs": @[@{@"id": tab, @"title": @"New tab", @"url": @"", @"pinned": @NO}]}]};
}
static BOOL ValidID(id value) {
    return [value isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:value] != nil;
}
NSDictionary *SLReadSession(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length > 4 * 1024 * 1024) return SLDefaultSession();
    id state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![state isKindOfClass:NSDictionary.class] || ![state[@"spaces"] isKindOfClass:NSArray.class]) return SLDefaultSession();
    NSMutableArray *spaces = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    for (id raw in state[@"spaces"]) {
        if (spaces.count >= 24) break;
        if (![raw isKindOfClass:NSDictionary.class] || !ValidID(raw[@"id"]) || [ids containsObject:raw[@"id"]] || ![raw[@"tabs"] isKindOfClass:NSArray.class]) continue;
        [ids addObject:raw[@"id"]];
        NSMutableArray *folders=[NSMutableArray array]; NSMutableSet *folderIDs=[NSMutableSet set];
        if ([raw[@"folders"] isKindOfClass:NSArray.class]) for (id folder in raw[@"folders"]) {
            if (folders.count>=100) break;
            if (![folder isKindOfClass:NSDictionary.class] || !ValidID(folder[@"id"]) || [ids containsObject:folder[@"id"]] || ![folder[@"name"] isKindOfClass:NSString.class]) continue;
            NSString *name=[folder[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!name.length) continue;
            [folderIDs addObject:folder[@"id"]]; [ids addObject:folder[@"id"]];
            [folders addObject:@{@"id":folder[@"id"],@"name":[name substringToIndex:MIN(name.length,48UL)],@"collapsed":@([folder[@"collapsed"] isKindOfClass:NSNumber.class] && [folder[@"collapsed"] boolValue])}];
        }
        NSMutableArray *tabs = [NSMutableArray array];
        NSString *emptyTabID=nil; BOOL activeWasEmpty=NO;
        for (id tab in raw[@"tabs"]) {
            if (tabs.count >= 200) break;
            if (![tab isKindOfClass:NSDictionary.class] || !ValidID(tab[@"id"]) || [ids containsObject:tab[@"id"]]) continue;
            NSString *url = tab[@"url"];
            if (![url isKindOfClass:NSString.class] || url.length > 32768 || (url.length && !SLIsExtensionsPage(url) && !SLTrustedExtensionURL(url) && !SLAllowedNavigation(url))) continue;
            url=SLPublicURL(url);
            if (!url.length) {
                if ([tab[@"id"] isEqual:raw[@"activeTab"]]) activeWasEmpty=YES;
                if (emptyTabID) continue;
                emptyTabID=tab[@"id"];
            }
            [ids addObject:tab[@"id"]];
            NSString *title = [tab[@"title"] isKindOfClass:NSString.class] ? tab[@"title"] : @"New tab";
            BOOL pinned=url.length && [tab[@"pinned"] isKindOfClass:NSNumber.class] && [tab[@"pinned"] boolValue];
            NSMutableDictionary *clean=[@{@"id": tab[@"id"], @"title": [title substringToIndex:MIN(title.length, 500UL)], @"url": url, @"pinned": @(pinned)} mutableCopy];
            if (pinned) {
                NSString *pinURL=tab[@"pinURL"];
                if (![pinURL isKindOfClass:NSString.class] || !pinURL.length || pinURL.length>32768 || !(SLAllowedNavigation(pinURL) || SLTrustedExtensionURL(pinURL) || SLIsExtensionsPage(pinURL))) pinURL=url;
                NSString *pinTitle=[tab[@"pinTitle"] isKindOfClass:NSString.class]?tab[@"pinTitle"]:title;
                clean[@"pinURL"]=SLPublicURL(pinURL); clean[@"pinTitle"]=[pinTitle substringToIndex:MIN(pinTitle.length,500UL)];
                if ([tab[@"folderID"] isKindOfClass:NSString.class] && [folderIDs containsObject:tab[@"folderID"]]) clean[@"folderID"]=tab[@"folderID"];
            }
            [tabs addObject:clean];
        }
        if (!tabs.count) [tabs addObject:@{@"id":SLNewID(), @"title":@"New tab", @"url":@"", @"pinned":@NO}];
        NSString *active = activeWasEmpty?emptyTabID:raw[@"activeTab"];
        if (![[tabs valueForKey:@"id"] containsObject:active ?: @""]) active = tabs[0][@"id"];
        NSString *name = [raw[@"name"] isKindOfClass:NSString.class] ? raw[@"name"] : @"Space";
        [spaces addObject:@{@"id":raw[@"id"], @"name":[name substringToIndex:MIN(name.length, 48UL)], @"tabs":tabs, @"activeTab":active, @"folders":folders}];
    }
    if (!spaces.count) return SLDefaultSession();
    NSString *active = state[@"activeSpace"];
    if (![[spaces valueForKey:@"id"] containsObject:active ?: @""]) active = spaces[0][@"id"];
    BOOL sidebar = ![state[@"sidebarVisible"] isKindOfClass:NSNumber.class] || [state[@"sidebarVisible"] boolValue];
    NSString *position=[@[@"bottom",@"right",@"left",@"window"] containsObject:state[@"devToolsPosition"] ?: @""] ? state[@"devToolsPosition"] : @"bottom";
    BOOL shield=![state[@"adblockEnabled"] isKindOfClass:NSNumber.class] || [state[@"adblockEnabled"] boolValue];
    NSMutableArray *hosts=[NSMutableArray array];
    if ([state[@"adblockPausedHosts"] isKindOfClass:NSArray.class]) for (id host in state[@"adblockPausedHosts"]) {
        if (hosts.count>=1000) break;
        if ([host isKindOfClass:NSString.class] && [host length]<254 && [host length]>0 && [[NSURLComponents componentsWithString:[@"https://" stringByAppendingString:host]].host.lowercaseString isEqual:host]) [hosts addObject:host];
    }
    return @{@"version":@1, @"spaces":spaces, @"activeSpace":active, @"sidebarVisible":@(sidebar), @"adblockEnabled":@(shield), @"adblockPausedHosts":hosts, @"devToolsPosition":position};
}
BOOL SLWriteSession(NSDictionary *state, NSString *path, NSError **error) {
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:error];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error];
}
