#import "Cloverleaf.h"
#import <objc/runtime.h>
#import <node.h>

NSMutableDictionary *nativeClassStorage;
NSMutableDictionary *nativeInstanceStorage;

@interface CLFunctionTemplate : NSObject
{
  v8::Handle<v8::FunctionTemplate> v8FunctionTemplate;
}

+ (id)dataWithV8FunctionTemplate:(v8::Handle<v8::FunctionTemplate>)v8FunctionTemplate;
- (id)initWithV8FunctionTemplate:(v8::Handle<v8::FunctionTemplate>)v8FunctionTemplate;
- (v8::Handle<v8::FunctionTemplate>)v8FunctionTemplate;

@end

@implementation CLFunctionTemplate

+ (id)dataWithV8FunctionTemplate:(v8::Handle<v8::FunctionTemplate>)v8FunctionTemplate
{
  return [[self alloc] initWithV8FunctionTemplate:v8FunctionTemplate];
}

- (id)initWithV8FunctionTemplate:(v8::Handle<v8::FunctionTemplate>)v8FunctionTemplate_
{
  [self init];
  v8FunctionTemplate = v8FunctionTemplate_;
  return self;
}

- (v8::Handle<v8::FunctionTemplate>)v8FunctionTemplate
{
  return v8FunctionTemplate;
}

@end

int MatchType(const char *type, const char *test)
{
  return strncmp(type, test, strlen(test)) == 0;
}

v8::Handle<v8::Value> CallNativeMethod(const v8::Arguments &args)
{
  id  target = (id)args.Holder()->GetPointerFromInternalField(0);
  SEL selector;
  int argumentCount = 0;
  if (args.Length() > 0)
  {
    argumentCount = args[0]->ToObject()->GetPropertyNames()->Length();
  }
  v8::Handle<v8::Value> arguments[argumentCount];
  if (args.IsConstructCall())
  {
    selector = @selector(alloc);
  }
  else
  {
    if (args.Callee()->GetName()->ToString()->Length())
    {
      selector = NSSelectorFromString([NSString stringWithCString:(const char *)*v8::String::AsciiValue(args.Callee()->GetName())
                                                         encoding:NSASCIIStringEncoding]);
    }
    else
    {
      v8::Handle<v8::Array> selectorKeys = args[0]->ToObject()->GetPropertyNames();
      NSMutableString *selectorString = [NSMutableString stringWithCapacity:200];
      for (int i = 0; i < selectorKeys->Length(); i++)
      {
          [selectorString appendString:[NSString stringWithCString:*v8::String::Utf8Value(selectorKeys->Get(i)) encoding:NSUTF8StringEncoding]];
          [selectorString appendString:@":"];
          arguments[i] = args[0]->ToObject()->Get(selectorKeys->Get(i));
      }
      selector = NSSelectorFromString(selectorString);
    }
  }
  if ([target class] == target)
    NSLog(@"Class Call: %s %s", class_getName([target class]), selector);
  else
    NSLog(@"Instance Call: %s %s", class_getName([target class]), selector);
  v8::HandleScope scope;
  if (![target respondsToSelector:selector])
    return v8::ThrowException(v8::Exception::TypeError(v8::String::New("object does not respond to selector")));
  NSMethodSignature *signature  = [target methodSignatureForSelector:selector];
  NSInvocation      *invocation = [NSInvocation invocationWithMethodSignature:signature];
  //
  // Convert v8 values to objc arguments and place in invocation
  //
  v8::Handle<v8::Value> v8_value;
  const char *type;
  // Start at index 2 for the invocation, because 0 and 1 are target and selector
  for (int i = 2; i < argumentCount + 2; i++)
  {
    type = [signature getArgumentTypeAtIndex:i];
    NSLog(@"Resolving argument: %s", type);
    v8_value = arguments[i - 2];
    if (MatchType(type, "@"))
    {
      if (v8_value->IsString())
      {
        NSString *s = [NSString stringWithCString:*v8::String::Utf8Value(v8_value->ToString()) encoding:NSUTF8StringEncoding];
        [invocation setArgument:&s atIndex:i];
      }
      else if (v8_value->IsObject())
      {
        id o = (id) v8_value->ToObject()->GetPointerFromInternalField(0);
        [invocation setArgument:&o atIndex:i];
      }
      else if (!v8_value->IsNull())
        return v8::ThrowException(v8::Exception::TypeError(v8::String::New("unhandled object argument")));
    }
    else if (MatchType(type, "{CGRect"))
    {
      NSRect rect = NSMakeRect(v8_value->ToObject()->Get(0)->ToNumber()->Value(),
                               v8_value->ToObject()->Get(1)->ToNumber()->Value(),
                               v8_value->ToObject()->Get(2)->ToNumber()->Value(),
                               v8_value->ToObject()->Get(3)->ToNumber()->Value());
      [invocation setArgument:&rect atIndex:i];
    }
    else if (MatchType(type, "Q"))
    {
      NSUInteger n = v8_value->ToUint32()->Value();
      [invocation setArgument:&n atIndex:i];
    }
    else if (MatchType(type, "c") || MatchType(type, "q"))
    {
      NSInteger n = v8_value->ToInt32()->Value();
      [invocation setArgument:&n atIndex:i];
    }
    // else if (MatchType(type, "*") || MatchType(type, "r*"))
    // {
    //   char *s = *v8::String::Utf8Value(v8_value);
    //   [invocation setArgument:&s atIndex:i];
    //   free(s);
    // }
    else if (MatchType(type, ":"))
    {
      if (!v8_value->IsNull())
      {
        SEL s = NSSelectorFromString([NSString stringWithCString:*v8::String::Utf8Value(v8_value->ToString()) encoding:NSUTF8StringEncoding]);
        [invocation setArgument:&s atIndex:i];
      }
    }
    else
      return v8::ThrowException(v8::Exception::TypeError(v8::String::New("unhandled argument")));
  }
  //
  // Invoke
  //
  [invocation setTarget:target];
  [invocation setSelector:selector];
  // Perform selector in the main thread, requires retaining arguments.  Need to make sure everything is properly
  // released.  Alternative is to invoke in this thread, but not sure if that will be thread safe generally.
  [invocation retainArguments];
  [invocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:YES];
  // At this point, go over all arguments and release any objects.
  for (unsigned i = 0; i < args.Length(); i++)
  {
    type = [signature getArgumentTypeAtIndex:i];
    if (MatchType(type, "@"))
    {
      NSLog(@"Releasing argument at index: %d", i);
      id arg;
      [invocation getArgument:&arg atIndex:i];
      [arg release];
    }
  }      
  //
  // Covert invocation objc response to v8 value
  //
  type = [signature methodReturnType];
  NSLog(@"Resolving result: %s", type);
  if (MatchType(type, "@"))
  {
    id o;
    [invocation getReturnValue:&o];
    if ([o isKindOfClass:[NSString class]])
    {
      v8_value = v8::String::New([(NSString *)o cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    else
    {
      NSLog(@"Wrap: %@", NSStringFromClass([o class]));
      v8::Handle<v8::FunctionTemplate> instanceConstructor = (
          [[nativeInstanceStorage objectForKey:NSStringFromClass([o class])] v8FunctionTemplate]);
      instanceConstructor->InstanceTemplate()->SetCallAsFunctionHandler(CallNativeMethod);
      v8_value = instanceConstructor->GetFunction()->NewInstance();
      v8_value->ToObject()->SetPointerInInternalField(0, o);
    }
    NSLog(@"Releasing result");
    [o release];
    return scope.Close(v8_value);
  }
  else if (MatchType(type, "{CGRect"))
  {
    NSRect *rect = new NSRect;
    [invocation getReturnValue:rect];
    v8_value = v8::Array::New(4);
    v8_value->ToObject()->Set(0, v8::Integer::New(rect->origin.x));
    v8_value->ToObject()->Set(1, v8::Integer::New(rect->origin.y));
    v8_value->ToObject()->Set(2, v8::Integer::New(rect->size.width));
    v8_value->ToObject()->Set(3, v8::Integer::New(rect->size.height));
    delete rect;
    return scope.Close(v8_value);
  }
  else if (MatchType(type, "v"))
  {
    return v8::Undefined();
  }
  return v8::ThrowException(v8::Exception::TypeError(v8::String::New("unhandled return type")));
}

void ExposeNativeClass(Class nativeClass)
{
  if ([nativeClassStorage objectForKey:NSStringFromClass(nativeClass)])
    return;
  NSLog(@"Expose:  %@", NSStringFromClass(nativeClass));
  v8::Persistent<v8::FunctionTemplate> classConstructor = v8::Persistent<v8::FunctionTemplate>::New(v8::FunctionTemplate::New());
  // v8::Handle<v8::FunctionTemplate> classConstructor = v8::FunctionTemplate::New();
  [nativeClassStorage setObject:[CLFunctionTemplate dataWithV8FunctionTemplate:classConstructor] forKey:NSStringFromClass(nativeClass)];
  if ([nativeClass class] != [NSObject class] && [nativeClass superclass])
  {
    ExposeNativeClass([nativeClass superclass]);
    v8::Handle<v8::FunctionTemplate> parentConstructor = (
        [[nativeClassStorage objectForKey:NSStringFromClass([nativeClass superclass])] v8FunctionTemplate]);
    NSLog(@"Inherit: %@ <- %@", NSStringFromClass(nativeClass), NSStringFromClass([nativeClass superclass]));
    classConstructor->Inherit(parentConstructor);
  }
  unsigned methodCount;
  const char *methodName;
  v8::Handle<v8::FunctionTemplate> methodTemplate;
  Method *methodList = class_copyMethodList(object_getClass(nativeClass), &methodCount);
  for (unsigned m = 0; m < methodCount; m++)
  {
    methodName = (const char *)method_getName(methodList[m]);
    if (strchr(methodName, '_'))
      continue;
    methodTemplate = v8::FunctionTemplate::New(CallNativeMethod);
    methodTemplate->GetFunction()->SetName(v8::String::New(methodName));
    classConstructor->PrototypeTemplate()->Set(v8::String::New(methodName), methodTemplate->GetFunction());
  }
  classConstructor->InstanceTemplate()->SetCallAsFunctionHandler(CallNativeMethod);
  classConstructor->InstanceTemplate()->SetInternalFieldCount(1);
  v8::Handle<v8::Object> classObject = classConstructor->GetFunction()->NewInstance();
  classObject->SetPointerInInternalField(0, nativeClass);
  v8::Context::GetCurrent()->Global()->Set(v8::String::New(class_getName(nativeClass)), classObject);
  // Set up instance prototype
  v8::Persistent<v8::FunctionTemplate> instanceConstructor = v8::Persistent<v8::FunctionTemplate>::New(v8::FunctionTemplate::New());
  instanceConstructor->InstanceTemplate()->SetInternalFieldCount(1);
  NSLog(@"Store:   %@ (Class Instance)", NSStringFromClass(nativeClass));
  [nativeInstanceStorage setObject:[CLFunctionTemplate dataWithV8FunctionTemplate:instanceConstructor] forKey:NSStringFromClass(nativeClass)];
  methodList = class_copyMethodList(nativeClass, &methodCount);
  for (unsigned m = 0; m < methodCount; m++)
  {
    methodName = (const char *)method_getName(methodList[m]);
    if (strchr(methodName, '_'))
      continue;
    methodTemplate = v8::FunctionTemplate::New(CallNativeMethod);
    methodTemplate->GetFunction()->SetName(v8::String::New(methodName));
    instanceConstructor->PrototypeTemplate()->Set(v8::String::New(methodName), methodTemplate->GetFunction());
  }
  methodTemplate = v8::FunctionTemplate::New(CallNativeMethod);
  methodTemplate->GetFunction()->SetName(v8::String::New("description"));
  instanceConstructor->PrototypeTemplate()->Set(v8::String::New("toString"), methodTemplate->GetFunction());
  if ([nativeClass class] != [NSObject class] && [nativeClass superclass])
  {
    v8::Handle<v8::FunctionTemplate> parentInstanceConstructor = (
        [[nativeInstanceStorage objectForKey:NSStringFromClass([nativeClass superclass])] v8FunctionTemplate]);
    instanceConstructor->Inherit(parentInstanceConstructor);
  }
}

void InitializeNativeBinding()
{
  nativeClassStorage    = [NSMutableDictionary dictionaryWithCapacity:100];
  nativeInstanceStorage = [NSMutableDictionary dictionaryWithCapacity:100];
  v8::HandleScope scope;
  const char *className;
  int classCount = objc_getClassList(nil, 0);
  Class classList[classCount];
  objc_getClassList(classList, classCount);
  for (int i = 0; i < classCount; i++)
  {
    className = class_getName(classList[i]);
    if (strncmp(className, "NS", 2) == 0 && strcmp(className, "NSMessageBuilder") != 0)
    {
      ExposeNativeClass(objc_getClass(className));
    }
  }
}

@implementation Cloverleaf

+ (id)sharedInstance
{
  static id sharedInstance = nil;
  @synchronized(self)
  {
    if (!sharedInstance) sharedInstance = [[Cloverleaf alloc] init];
  }
  return sharedInstance;
}

- (void)start
{
  [[NSAutoreleasePool alloc] init];
  if (thread)
  {
    NSMutableString *nodepath = [NSMutableString stringWithCapacity:500];
    [nodepath appendString:[[[NSBundle bundleForClass:[self class]] resourcePath] stringByAppendingPathComponent:@"lib"]];
    [nodepath appendString:@":"];
    [nodepath appendString:[[NSBundle mainBundle] resourcePath]];
    setenv("NODE_PATH", [nodepath cStringUsingEncoding:NSUTF8StringEncoding], YES);
    char **argv = (char **)calloc(sizeof(char *), 2);
    argv[0] = (char *)[[[NSProcessInfo processInfo] processName] cStringUsingEncoding:NSUTF8StringEncoding];
    argv[1] = (char *)[[[NSBundle bundleForClass:[self class]] pathForResource:@"main" ofType:@"js" inDirectory:@"lib"] cStringUsingEncoding:NSUTF8StringEncoding];
    node::Initialize(2, argv);
    free(argv);
    node::GetContext()->Enter();
    InitializeNativeBinding();
    node::GetContext()->Exit();
    node::Run();
  }
  else
  {
    thread = [[NSThread alloc] initWithTarget:self selector:@selector(start) object:nil];
    [thread start];
  }
}

@end
