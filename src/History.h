#import <Foundation/Foundation.h>

// One bounded, local history store per space. Never sends queries to a service.
@interface SLHistory : NSObject
@property(nonatomic, readonly) NSArray<NSDictionary *> *entries;
- (instancetype)initWithPath:(NSString *)path;
- (void)visit:(NSString *)url title:(NSString *)title;
- (void)updateTitle:(NSString *)title forURL:(NSString *)url;
- (NSArray<NSDictionary *> *)suggestions:(NSString *)query tabs:(NSArray<NSDictionary *> *)tabs;
- (BOOL)save;
- (void)clear;
@end
NSString *SLHistoryURL(NSString *url);
NSString *SLCompletion(NSString *query, NSString *url);
