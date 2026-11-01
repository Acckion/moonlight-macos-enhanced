#import "MLFullscreenPresentation.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        NSApplicationPresentationOptions proposed = NSApplicationPresentationFullScreen |
            NSApplicationPresentationHideDock | NSApplicationPresentationAutoHideMenuBar |
            NSApplicationPresentationAutoHideToolbar | NSApplicationPresentationDisableAppleMenu;
        NSApplicationPresentationOptions show = MLFullscreenPresentationOptions(proposed, YES);
        assert(show & NSApplicationPresentationFullScreen);
        assert(show & NSApplicationPresentationAutoHideDock);
        assert(show & NSApplicationPresentationAutoHideMenuBar);
        assert(!(MLFullscreenPresentationOptions(0, YES) & NSApplicationPresentationAutoHideMenuBar));
        assert(show & NSApplicationPresentationDisableAppleMenu);
        assert(!(show & (NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar | NSApplicationPresentationAutoHideToolbar)));
        NSApplicationPresentationOptions hide = MLFullscreenPresentationOptions(show, NO);
        assert(hide & NSApplicationPresentationHideMenuBar);
        assert(!(hide & NSApplicationPresentationAutoHideMenuBar));
        assert(MLFullscreenPresentationOptions(hide, YES) == show);
        assert(MLFullscreenPresentationOptions(show, YES) == show);
        NSRect screen = NSMakeRect(-1920, 100, 1920, 1080);
        NSRect visible = MLBorderlessFrame(screen, 0, NO, YES, 24);
        assert(visible.origin.x == -1920 && visible.origin.y == 100);
        assert(visible.size.width == 1920 && visible.size.height == 1056);
        assert(NSEqualRects(MLBorderlessFrame(screen, 0, NO, NO, 24), screen));
        assert(MLBorderlessFrame(screen, 38, NO, YES, 24).size.height == 1042);
        assert(MLBorderlessFrame(screen, 38, YES, NO, 24).size.height == 1042);
        assert(MLBorderlessFrame(screen, 38, NO, NO, 24).size.height == 1080);
        assert(MLBorderlessFrame(NSMakeRect(0, 0, 10, 10), 38, YES, YES, 24).size.height == 0);
        puts("Fullscreen menu-bar presentation and geometry tests passed.");
    }
}
