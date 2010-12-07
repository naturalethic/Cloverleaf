#import "V8FunctionTemplate.h"

@implementation V8FunctionTemplate

+ (id)functionTemplateWithHandle:(v8::Handle<v8::FunctionTemplate>)handle
{
  return [[self alloc] initWithHandle:handle];
}

- (id)initWithHandle:(v8::Handle<v8::FunctionTemplate>)handle_
{
  [self init];
  handle = handle_;
  return self;
}

- (v8::Handle<v8::FunctionTemplate>)handle
{
  return handle;
}

@end
