// sim_hw_keyboard — attach/detach the simulated hardware keyboard without Simulator.app (Xcode 27 ships none).
// Uses the private SimulatorKit category on SimDevice: -setHardwareKeyboardEnabled:keyboardType:error:
// Usage: sim_hw_keyboard <UDID> on|off
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>
int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 3) { fprintf(stderr, "usage: %s <UDID> on|off\n", argv[0]); return 2; }
    NSString *udid = [NSString stringWithUTF8String:argv[1]];
    BOOL enable = strcmp(argv[2], "on") == 0;
    if (!dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW)) { fprintf(stderr, "dlopen CoreSimulator: %s\n", dlerror()); return 3; }
    if (!dlopen("/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit", RTLD_NOW)) { fprintf(stderr, "dlopen SimulatorKit: %s\n", dlerror()); return 3; }
    Class ctxClass = NSClassFromString(@"SimServiceContext");
    if (!ctxClass) { fprintf(stderr, "no SimServiceContext\n"); return 3; }
    NSError *err = nil;
    id ctx = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(ctxClass, NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"), @"/Applications/Xcode.app/Contents/Developer", &err);
    if (!ctx) { fprintf(stderr, "context error: %s\n", err.description.UTF8String); return 4; }
    id set = ((id (*)(id, SEL, NSError **))objc_msgSend)(ctx, NSSelectorFromString(@"defaultDeviceSetWithError:"), &err);
    if (!set) { fprintf(stderr, "device set error: %s\n", err.description.UTF8String); return 4; }
    NSArray *devices = ((id (*)(id, SEL))objc_msgSend)(set, NSSelectorFromString(@"devices"));
    for (id dev in devices) {
      NSUUID *u = ((id (*)(id, SEL))objc_msgSend)(dev, NSSelectorFromString(@"UDID"));
      if (![u.UUIDString isEqualToString:udid]) continue;
      SEL sel = NSSelectorFromString(@"setHardwareKeyboardEnabled:keyboardType:error:");
      if (![dev respondsToSelector:sel]) { fprintf(stderr, "SimDevice does not respond to %s\n", sel_getName(sel)); return 5; }
      BOOL ok = ((BOOL (*)(id, SEL, BOOL, NSInteger, NSError **))objc_msgSend)(dev, sel, enable, 0, &err);
      printf("%s hardware keyboard %s: %s%s\n", udid.UTF8String, enable ? "on" : "off", ok ? "ok" : "FAILED", ok ? "" : err.description.UTF8String);
      return ok ? 0 : 6;
    }
    fprintf(stderr, "device %s not found\n", udid.UTF8String); return 7;
  }
}
