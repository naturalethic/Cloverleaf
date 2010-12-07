#import "V8Value.h"

@implementation V8Value

+ (id)valueWithHandle:(v8::Handle<v8::Value>)handle
{
  return [[self alloc] initWithHandle:handle];
}

- (id)initWithHandle:(v8::Handle<v8::Value>)handle_
{
  [self init];
  handle = handle_;
  return self;
}

- (v8::Handle<v8::Value>)handle
{
  return handle;
}

- (BOOL)isFunction
{
  return handle->IsFunction();
}

@end
