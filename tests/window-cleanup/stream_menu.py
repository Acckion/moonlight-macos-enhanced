"""Exercise production menu ownership against real AppKit menu objects (no windows)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Limelight/macOS/ViewControllers/StreamViewController+MenuUI.m').read_text()
start = source.index('- (void)installStreamMenuBarItemIfNeeded {')
methods = source[start:source.index('- (void)installStreamMenuEntrypoints {', start)]
fixture = r'''
#import <Cocoa/Cocoa.h>
#include <assert.h>
#define MLString(key, comment) (key)
@interface TestApp : NSObject
@property NSMenu *mainMenu;
@property NSMenu *windowsMenu;
@end
@implementation TestApp
@end
static TestApp *testApp;
#undef NSApp
#define NSApp testApp
@interface TestView : NSObject
@property id window;
@end
@implementation TestView
@end
@interface StreamViewController : NSObject
@property TestView *view;
@property BOOL stopStreamInProgress;
@property NSMenu *streamMenu;
@property NSMenuItem *streamMenuBarItem;
@property int builds;
- (void)rebuildStreamMenu;
- (void)installStreamMenuBarItemIfNeeded;
- (void)removeStreamMenuBarItem;
@end
@implementation StreamViewController
- (void)rebuildStreamMenu { self.builds++; self.streamMenu = [[NSMenu alloc] initWithTitle:@"Shared"]; }
'''
checks = r'''
@end
static StreamViewController *owner(void) {
    StreamViewController *c = [StreamViewController new];
    c.view = [TestView new]; c.view.window = [NSObject new]; return c;
}
int main(void) { @autoreleasepool {
    testApp = [TestApp new]; testApp.mainMenu = [NSMenu new]; testApp.windowsMenu = [NSMenu new];
    [testApp.mainMenu addItemWithTitle:@"App" action:NULL keyEquivalent:@""];
    NSMenuItem *windows = [testApp.mainMenu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
    windows.submenu = testApp.windowsMenu;
    [testApp.mainMenu addItemWithTitle:@"Help" action:NULL keyEquivalent:@""];
    StreamViewController *a = owner(), *b = owner();
    [a installStreamMenuBarItemIfNeeded];
    assert([testApp.mainMenu itemAtIndex:1] == a.streamMenuBarItem);
    assert(a.streamMenuBarItem.submenu == a.streamMenu);
    [a installStreamMenuBarItemIfNeeded];
    assert(testApp.mainMenu.numberOfItems == 4 && a.builds == 1);
    [b installStreamMenuBarItemIfNeeded];
    assert(testApp.mainMenu.numberOfItems == 4 && [testApp.mainMenu itemAtIndex:1] == b.streamMenuBarItem);
    [a removeStreamMenuBarItem]; // A delayed close must not remove the newer owner's entry.
    assert(testApp.mainMenu.numberOfItems == 4 && b.streamMenuBarItem.menu == testApp.mainMenu);
    [b removeStreamMenuBarItem]; [b removeStreamMenuBarItem];
    assert(testApp.mainMenu.numberOfItems == 3);
    a.stopStreamInProgress = YES; [a installStreamMenuBarItemIfNeeded]; assert(!a.streamMenuBarItem);
    a.stopStreamInProgress = NO; a.view.window = nil;
    [a installStreamMenuBarItemIfNeeded]; assert(!a.streamMenuBarItem);
    puts("PASS: one shared stream menu before Window; focus ownership, stale/repeated cleanup, stopped/missing windows");
} }
'''
with tempfile.TemporaryDirectory(prefix='moonlight-menu-owner-test-') as tmp:
    path = Path(tmp)
    (path / 'test.m').write_text(fixture + methods + checks)
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Cocoa', str(path / 'test.m'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)
