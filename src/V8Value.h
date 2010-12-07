#import <Cocoa/Cocoa.h>
#import <v8.h>

@interface V8Value : NSObject
{
  v8::Handle<v8::Value> handle;
}

+ (id)valueWithHandle:(v8::Handle<v8::Value>)handle;
- (id)initWithHandle:(v8::Handle<v8::Value>)handle;
- (v8::Handle<v8::Value>)handle;
- (BOOL)isFunction;

@end
