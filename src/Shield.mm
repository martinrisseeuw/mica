#import "Shield.h"
#include <mutex>

static NSDictionary *rules;
static BOOL enabled=YES;
static NSSet<NSString *> *paused;
static std::mutex settingsMutex;
static NSString *Host(NSString *url) {
    NSString *host=[NSURLComponents componentsWithString:url].host.lowercaseString ?: @"";
    return [host hasSuffix:@"."] ? [host substringToIndex:host.length-1] : host;
}
static BOOL Matches(NSString *host, NSString *domain) {
    return [host isEqual:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]];
}
BOOL SLShieldLoad(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"domains"] isKindOfClass:NSArray.class] || ![value[@"selectors"] isKindOfClass:NSArray.class]) return NO;
    rules=value; // Loaded once before starting CEF; immutable on request threads.
    return YES;
}
void SLShieldConfigure(BOOL on, NSArray<NSString *> *hosts) {
    std::lock_guard<std::mutex> lock(settingsMutex);
    enabled=on; paused=[NSSet setWithArray:hosts];
}
BOOL SLShieldEnabledForURL(NSString *url) {
    std::lock_guard<std::mutex> lock(settingsMutex);
    return enabled && rules && ![paused containsObject:Host(url)];
}
BOOL SLShieldShouldBlock(NSString *url, NSString *topURL) {
    @autoreleasepool {
        if (!SLShieldEnabledForURL(topURL)) return NO;
        NSURLComponents *parts=[NSURLComponents componentsWithString:url];
        if (![@[@"http",@"https"] containsObject:parts.scheme.lowercaseString]) return NO;
        NSString *host=Host(url), *top=Host(topURL), *path=parts.path ?: @"";
        if (!top.length) return NO;
        BOOL youtube=Matches(top,@"youtube.com") || Matches(top,@"youtube-nocookie.com");
        if (youtube && [host isEqual:@"static.doubleclick.net"] && [path hasPrefix:@"/instream/ad_status.js"]) return NO;
        if (Matches(host,@"youtube.com")) {
            for (NSString *prefix in rules[@"youtubePaths"]) if ([path hasPrefix:prefix]) return YES;
            if ([path isEqual:@"/api/stats/qoe"] && [parts.query containsString:@"adformat="]) return YES;
        }
        if (youtube && ((Matches(host,@"google.com") && [path hasPrefix:@"/pagead/"]) || [host isEqual:@"imasdk.googleapis.com"])) return YES;
        for (NSString *domain in rules[@"domains"]) if (Matches(host,domain)) {
            // Every curated domain in Search's list has a one-label public
            // suffix. Compare its registrable base to preserve first-party
            // requests, including e.g. google.com -> adservice.google.com.
            NSArray *labels=[domain componentsSeparatedByString:@"."];
            NSString *base=[[labels subarrayWithRange:NSMakeRange(labels.count-2,2)] componentsJoinedByString:@"."];
            return !Matches(top,base);
        }
        return NO;
    }
}
NSString *SLShieldCosmeticScript(NSString *topURL, NSString *frameURL) {
    if (!SLShieldEnabledForURL(topURL)) return @"document.getElementById('searchlight-adblock-style')?.remove();";
    NSMutableArray *selectors=[rules[@"selectors"] mutableCopy];
    NSString *host=Host(frameURL);
    for (NSDictionary *site in rules[@"siteSelectors"]) for (NSString *domain in site[@"hosts"]) if (Matches(host,domain)) {
        [selectors addObject:site[@"selector"]]; break;
    }
    NSString *css=[NSString stringWithFormat:@"%@ { display: none !important; }",[selectors componentsJoinedByString:@", "]];
    NSData *json=[NSJSONSerialization dataWithJSONObject:@[css] options:0 error:nil];
    NSString *encoded=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:@"(()=>{let s=document.getElementById('searchlight-adblock-style');if(!s){s=document.createElement('style');s.id='searchlight-adblock-style';(document.head||document.documentElement).append(s)}s.textContent=%@[0]})()",encoded];
}
