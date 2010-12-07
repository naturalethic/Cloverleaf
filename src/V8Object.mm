#import "V8Object.h"
#import "V8Function.h"

@implementation V8Object

- (id)init
{
  handle = v8::Object::New();
  return self;
}

+ (id)object
{
  return [[self alloc] init];
}

+ (id)objectWithHandle:(v8::Handle<v8::Object>)handle
{
  return [[self alloc] initWithHandle:handle];
}

- (v8::Handle<v8::Object>)handle
{
  return handle;
}

- (BOOL)hasKey:(NSString *)key
{
  return [self handle]->Has(v8::String::New([key cStringUsingEncoding:NSUTF8StringEncoding]));
}

- (V8Value *)valueForKey:(NSString *)key
{
  if ([self hasKey:key])
  {
    v8::Handle<v8::Value> value = [self handle]->Get(v8::String::New([key cStringUsingEncoding:NSUTF8StringEncoding]));
    if (value->IsFunction())
      return [V8Function functionWithHandle:value];
//    V8Value *value = [V8Value valueWithHandle:[self handle]->Get(v8::String::New([key cStringUsingEncoding:NSUTF8StringEncoding]))];
    return [V8Value valueWithHandle:value];
  }
  return nil;
}
@end
