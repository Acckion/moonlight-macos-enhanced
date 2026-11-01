#import <Cocoa/Cocoa.h>

// Keep Dock/menu-bar combinations valid, including proposed AppKit toolbar flags.
static inline NSApplicationPresentationOptions MLFullscreenPresentationOptions(
    NSApplicationPresentationOptions proposed, BOOL showMenuBar) {
    proposed &= ~(NSApplicationPresentationHideDock |
                  NSApplicationPresentationAutoHideDock |
                  NSApplicationPresentationAutoHideMenuBar |
                  NSApplicationPresentationHideMenuBar |
                  NSApplicationPresentationAutoHideToolbar);
    if (showMenuBar) {
        proposed |= NSApplicationPresentationAutoHideDock;
        // Native fullscreen requires AppKit's automatic menu-bar management.
        // Its per-app AppleMenuBarVisibleInFullscreen preference determines whether
        // the bar remains visible; stripping this flag forces immersive presentation.
        if (proposed & NSApplicationPresentationFullScreen) {
            proposed |= NSApplicationPresentationAutoHideMenuBar;
        }
    } else {
        proposed |= NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
    }
    return proposed;
}

// Reserve only the top strip. visibleFrame would also reserve a hidden Dock's space.
static inline NSRect MLBorderlessFrame(NSRect screen, CGFloat notchHeight,
                                      BOOL avoidNotch, BOOL showMenuBar, CGFloat menuBarHeight) {
    CGFloat inset = avoidNotch ? notchHeight : 0;
    if (showMenuBar) inset = MAX(notchHeight, menuBarHeight);
    screen.size.height = MAX(0, screen.size.height - inset);
    return screen;
}
