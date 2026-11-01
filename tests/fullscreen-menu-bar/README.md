# Fullscreen menu bar option

Run on macOS:

```sh
clang -fobjc-arc -framework Cocoa -I Limelight/macOS/Helpers tests/fullscreen-menu-bar/presentation.m -o /tmp/moonlight-menu-bar-tests
/tmp/moonlight-menu-bar-tests
python3 tests/window-cleanup/run.py
python3 scripts/generate_settings_search_index.py --check
```

The geometry checks cover notched and ordinary displays, negative secondary-display origins, valid AppKit presentation flags, idempotent toggles, and no Dock-sized bottom gap. Window cleanup checks ensure a pending menu refresh cannot take priority over disconnect/close, and a failed fullscreen exit clears the pending refresh.

Manual acceptance is required: choose a host profile, enable the option, and stream Desktop. Check native and borderless fullscreen with the pointer away from the top. Toggle off/on in the stream control menu; check that the stream stays connected, menus remain clickable, and the picture starts below the visible bar. Exit fullscreen, switch applications, and confirm their normal menu-bar behavior. Reopen settings to check persistence, including old profiles that lack the optional field.

A captured stream-window image excludes the macOS menu bar outside its bounds. Legacy `NSMenu.menuBarVisible` and a requested presentation mask alone do not establish what the user sees in a native fullscreen Space. Verify the actual screen before claiming acceptance.
