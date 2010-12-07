#import <Cocoa/Cocoa.h>
#import "V8Object.h"

@interface V8Array : V8Object
{
}

+ (id)array;
+ (id)arrayWithHandle:(v8::Handle<v8::Array>)handle;
- (v8::Handle<v8::Array>)handle;
- (int)length;
- (V8Value *)objectAtIndex:(int)index;

@end
