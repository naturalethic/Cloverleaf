#import <Cocoa/Cocoa.h>
#import "V8Object.h"
#import "V8Array.h"

@interface V8Function : V8Object
{
}

+ (id)functionWithHandle:(v8::Handle<v8::Function>)handle;
- (v8::Handle<v8::Function>)handle;
- (V8Value *)callWithReceiver:(V8Object *)receiver arguments:(V8Array *)arguments;

@end
