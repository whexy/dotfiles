#import <Cocoa/Cocoa.h>

@interface Handler : NSObject
@end

@implementation Handler
- (void)handleURL:(NSAppleEventDescriptor *)event
    withReplyEvent:(NSAppleEventDescriptor *)reply {
  (void)reply;
  NSString *url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
  if (url == nil) return;
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@SCRIPT];
  task.arguments = @[ url ];
  NSError *error = nil;
  if (![task launchAndReturnError:&error]) NSLog(@"neovide-remote: %@", error);
}

/* Each link is served by its own script process, which outlives this app;
 * staying resident would only leave an invisible process behind. */
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:2.0];
}
@end

int main(void) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    Handler *handler = [[Handler alloc] init];
    app.delegate = (id<NSApplicationDelegate>)handler;
    [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:handler
            andSelector:@selector(handleURL:withReplyEvent:)
          forEventClass:kInternetEventClass
             andEventID:kAEGetURL];
    [app run];
  }
  return 0;
}
