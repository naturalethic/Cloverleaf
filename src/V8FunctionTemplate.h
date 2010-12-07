#import <Cocoa/Cocoa.h>
#import <v8.h>

@interface V8FunctionTemplate : NSObject
{
  v8::Handle<v8::FunctionTemplate> handle;
}

+ (id)functionTemplateWithHandle:(v8::Handle<v8::FunctionTemplate>)handle;
- (id)initWithHandle:(v8::Handle<v8::FunctionTemplate>)handle;
- (v8::Handle<v8::FunctionTemplate>)handle;

@end
