#import "V8Function.h"

@implementation V8Function

+ (id)functionWithHandle:(v8::Handle<v8::Function>)handle
{
  return [[self alloc] initWithHandle:handle];
}

- (v8::Handle<v8::Function>)handle
{
  return handle;
}

- (V8Value *)callWithReceiver:(V8Object *)receiver arguments:(V8Array *)arguments
{
  v8::Handle<v8::Value> argv[[arguments length]];
  for (int i; i < [arguments length]; i++)
  {
    argv[i] = [[arguments objectAtIndex:i] handle];
  }
  [self handle]->Call([receiver handle], [arguments length], argv);
  return nil;
}

@end
