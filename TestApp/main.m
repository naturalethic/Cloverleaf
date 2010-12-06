#import "Cloverleaf.h"

int main(int argc, char *argv[])
{
  [[Cloverleaf sharedInstance] start];
  return NSApplicationMain(argc,  (const char **) argv);
}
