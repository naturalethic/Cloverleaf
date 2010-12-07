#import <Cocoa/Cocoa.h>
#import "V8Value.h"

@interface V8Object : V8Value
{
}

+ (id)object;
+ (id)objectWithHandle:(v8::Handle<v8::Object>)handle;
- (v8::Handle<v8::Object>)handle;
- (BOOL)hasKey:(NSString *)key;
- (V8Value *)valueForKey:(NSString *)key;

@end
