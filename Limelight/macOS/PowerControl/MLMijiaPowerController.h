#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface MLMijiaPowerController : NSObject
+ (instancetype)shared;
- (NSMenuItem *)menuItemForHostUUID:(NSString *)uuid name:(NSString *)name;
@end
NS_ASSUME_NONNULL_END
