#import <AppKit/AppKit.h>

extern void DianyuRunApplication(void);

// Establish AppKit's application/run-loop integration before creating any Swift
// actor, view, or menu. SwiftUI remains a view host, not the process/scene owner.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DianyuRunApplication();
    }
    return 0;
}
