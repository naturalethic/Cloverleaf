#import "V8Array.h"

@implementation V8Array

- (id)init
{
  handle = v8::Array::New();
  return self;
}

+ (id)array;
{
  return [[self alloc] init];
}

+ (id)arrayWithHandle:(v8::Handle<v8::Array>)handle
{
  return [[self alloc] initWithHandle:handle];
}

- (v8::Handle<v8::Array>)handle
{
  return handle;
}

- (int)length
{
  return [self handle]->Length();
}

- (V8Value *)objectAtIndex:(int)index
{
  return [V8Value valueWithHandle:[self handle]->Get(index)];
}

@end
