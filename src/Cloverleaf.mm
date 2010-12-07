#import "Cloverleaf.h"
#import "V8Value.h"
#import "V8Object.h"
#import "V8Array.h"
#import "V8Function.h"
#import "V8FunctionTemplate.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <node.h>

NSMutableDictionary *nativeClassStorage;
NSMutableDictionary *nativeInstanceStorage;
NSMutableDictionary *userClassStorage;

BOOL MatchType(const char *type, const char *test)
{
  return strncmp(type, test, strlen(test)) == 0;
}

@interface CLProxy : NSProxy
{
  NSObject *parent;  // The prototype (cocoa instance)
  V8Object *object;  // The prototype
  V8Object *myself;  // The instance
}

@end

// XXX: This whole thing needs to be checked for thread safety.
@implementation CLProxy

- (id)init
{
  NSLog(@"Initializing proxy: %@", [self class]);
  object = (V8Object *)[userClassStorage objectForKey:[NSString stringWithCString:class_getName([self class]) encoding:NSASCIIStringEncoding]];
  parent = (id)[object handle]->GetPointerFromInternalField(0);
  myself = [V8Object object];
  NSLog(@"Parent: %@", parent);
  return self;
}

- (BOOL)respondsToSelector:(SEL)selector
{
  NSLog(@"respondsToSelector: %s parent: %d", selector, [parent respondsToSelector:selector]);
  if ([object hasKey:NSStringFromSelector(selector)])
  {
    V8Value *value = [object valueForKey:NSStringFromSelector(selector)];
    if ([value isFunction])
    {
      return YES;
    }
  }
  return [parent respondsToSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
  NSLog(@"forwardInvocation: %s", [invocation selector]);
  if ([object hasKey:NSStringFromSelector([invocation selector])])
  {
    V8Value *value = [object valueForKey:NSStringFromSelector([invocation selector])];
    if ([value isKindOfClass:[V8Function class]])
    {
      V8Array *arguments = [V8Array array];
      for (int i = 2; i < [[invocation methodSignature] numberOfArguments]; i++)
      {
//        const char *type = [[invocation methodSignature] getArgumentTypeAtIndex:i];
//        [arguments push:
      }
      [(V8Function *)value callWithReceiver:myself arguments:arguments];
      return;
    }
  }
  [invocation invokeWithTarget:parent];
}

// iOS 4 only
// - (id)forwardingTargetForSelector:(SEL)selector
// {
//   NSLog(@"forwardingTargetForSelector: %s", selector);
//   return parent;
// }

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
  NSLog(@"methodSignatureForSelector: %s", selector);
  return [parent methodSignatureForSelector:selector];
}

// dealloc needs to be defined to remove the persistent object

@end


v8::Handle<v8::Value> RegisterUserClass(const v8::Arguments &args)
{
  v8::HandleScope scope;
  const char *name = (const char *)*v8::String::AsciiValue(args[0]);
  Class parent = (Class)args[1]->ToObject()->GetPointerFromInternalField(0);
//  Class userClass = objc_allocateClassPair(parent, name, 0);
  Class userClass = objc_allocateClassPair([CLProxy class], name, 0);
  NSLog(@"Register: %s <- %@", name, parent);
//  class_addMethod(userClass, @selector(respondsToSelector:), (IMP)UserClassRespondsToSelector, "B@::");
//  class_addMethod(userClass, @selector(doesNotRecognizeSelector:), (IMP)UserClassDoesNotRecognizeSelector, "v@::");
//  class_addMethod(userClass, @selector(forwardInvocation:), (IMP)UserClassForwardInvocation, "v@:@");
  //class_addMethod(userClass, @selector(methodSignatureForSelector:), (IMP)UserClassMethodSignatureForSelector, "@@::");
  objc_registerClassPair(userClass);
  v8::Handle<v8::ObjectTemplate> userClassTemplate = v8::ObjectTemplate::New();
  userClassTemplate->SetInternalFieldCount(1);
  v8::Handle<v8::Object> userClassInstance = v8::Persistent<v8::Object>::New(userClassTemplate->NewInstance());
  userClassInstance->SetPointerInInternalField(0, [[parent alloc] init]);
  v8::Handle<v8::Array> definedKeys = args[2]->ToObject()->GetPropertyNames();
  for (int i = 0; i < definedKeys->Length(); i++)
  {
    userClassInstance->Set(definedKeys->Get(i), args[2]->ToObject()->Get(definedKeys->Get(i)));
  }
  [userClassStorage setObject:[V8Object objectWithHandle:userClassInstance] forKey:[NSString stringWithCString:name encoding:NSASCIIStringEncoding]];
  return v8::Undefined();
}

v8::Handle<v8::Value> CallNativeMethod(const v8::Arguments &args)
{
  v8::HandleScope scope;
  id  target = (id)args.Holder()->GetPointerFromInternalField(0);
  SEL selector;
  int argumentCount = 0;
  if (args.Length() > 0)
  {
    // if (args[0]->IsString())
    // {
    //   return RegisterUserClass(target, *v8::String::AsciiValue(args[0]));
    // }
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
          [[nativeInstanceStorage objectForKey:NSStringFromClass([o class])] handle]);
      instanceConstructor->InstanceTemplate()->SetCallAsFunctionHandler(CallNativeMethod);
      v8_value = instanceConstructor->GetFunction()->NewInstance();
      v8_value->ToObject()->SetPointerInInternalField(0, o);
    }
    //NSLog(@"Releasing result");
    //[o release];
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
  // NSLog(@"Expose:  %@", NSStringFromClass(nativeClass));
  v8::Persistent<v8::FunctionTemplate> classConstructor = v8::Persistent<v8::FunctionTemplate>::New(v8::FunctionTemplate::New());
  // v8::Handle<v8::FunctionTemplate> classConstructor = v8::FunctionTemplate::New();
  [nativeClassStorage setObject:[V8FunctionTemplate functionTemplateWithHandle:classConstructor] forKey:NSStringFromClass(nativeClass)];
  if ([nativeClass class] != [NSObject class] && [nativeClass superclass])
  {
    ExposeNativeClass([nativeClass superclass]);
    v8::Handle<v8::FunctionTemplate> parentConstructor = (
        [[nativeClassStorage objectForKey:NSStringFromClass([nativeClass superclass])] handle]);
    // NSLog(@"Inherit: %@ <- %@", NSStringFromClass(nativeClass), NSStringFromClass([nativeClass superclass]));
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
  // NSLog(@"Store:   %@ (Class Instance)", NSStringFromClass(nativeClass));
  [nativeInstanceStorage setObject:[V8FunctionTemplate functionTemplateWithHandle:instanceConstructor] forKey:NSStringFromClass(nativeClass)];
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
        [[nativeInstanceStorage objectForKey:NSStringFromClass([nativeClass superclass])] handle]);
    instanceConstructor->Inherit(parentInstanceConstructor);
  }
}

void InitializeNativeBinding()
{
  nativeClassStorage    = [NSMutableDictionary dictionaryWithCapacity:100];
  nativeInstanceStorage = [NSMutableDictionary dictionaryWithCapacity:100];
  userClassStorage      = [NSMutableDictionary dictionaryWithCapacity:100];
  const char *className;
  int classCount = objc_getClassList(nil, 0);
  Class classList[classCount];
  objc_getClassList(classList, classCount);
  for (int i = 0; i < classCount; i++)
  {
    className = class_getName(classList[i]);
    if (strcmp(className, "NSMessageBuilder") != 0 && 
        (strncmp(className, "NS", 2) == 0 || strcmp(className, "Cloverleaf") == 0))
    {
      ExposeNativeClass(objc_getClass(className));
    }
  }
  v8::Handle<v8::FunctionTemplate> registerTemplate = v8::FunctionTemplate::New(RegisterUserClass);
  v8::Context::GetCurrent()->Global()->Set(v8::String::New("Class"), registerTemplate->GetFunction());
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

+ (void)loadMainNib
{
  if ([NSThread isMainThread])
  {
    NSString *mainNibName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"NSMainNibFile"];
    NSNib *mainNib = [[NSNib alloc] initWithNibNamed:mainNibName bundle:[NSBundle mainBundle]];
    [mainNib instantiateNibWithOwner:NSApp topLevelObjects:nil];
  }
  else 
  {
    [Cloverleaf performSelectorOnMainThread:@selector(loadMainNib) withObject:nil waitUntilDone:NO];
  }
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
    v8::HandleScope scope;
    InitializeNativeBinding();
    node::Run();
    NSLog(@"Node exited");
  }
  else
  {
    thread = [[NSThread alloc] initWithTarget:self selector:@selector(start) object:nil];
    [thread start];
    [[NSClassFromString([[[NSBundle mainBundle] infoDictionary] objectForKey:@"NSPrincipalClass"]) sharedApplication] run];
  }
}

@end
