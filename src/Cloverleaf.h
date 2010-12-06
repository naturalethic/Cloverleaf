#import <Cocoa/Cocoa.h>

@interface Cloverleaf : NSObject
{
  NSThread *thread;
}

+ (id)sharedInstance;
- (void)start;

@end
