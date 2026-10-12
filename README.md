# MouseControl

A native macOS 27 menu-bar app that replaces the parts of Logi Options+ used with an MX Master 3S: mouse-only scroll direction, thumb-wheel direction, DPI, Back/Forward in Safari, thumb button → Mission Control, and battery.

## Layout

| Path | What |
|---|---|
| `App/` | SwiftUI `MenuBarExtra`, `DeviceController`, `EventTapService`, settings, permissions |
| `Packages/MouseControlKit/` | HID++ 2.0 framing/matching (`HIDPPChannel`), features, `IOHIDManager` transport. No AppKit dependency, so it can be tested without hardware. |
| `project.yml` | xcodegen spec (`MouseControl.xcodeproj` is generated from it) |
| `Scripts/release.sh` | Archive → Developer ID sign → notarize → staple |

## Build & test

```bash
xcodegen generate
xcodebuild -project MouseControl.xcodeproj -scheme MouseControl build
swift test --package-path Packages/MouseControlKit
```

## First run

1. Quit and uninstall Logi Options+; it diverts the same controls.
2. Grant **Input Monitoring** (opens the mouse's HID++ channel) and **Accessibility** (event tap and key posting). The menu links to both panes. macOS may require a relaunch after granting Input Monitoring; the menu offers it.
3. The app registers itself as a login item on first launch.

## Debugging

```bash
log stream --level debug --predicate 'subsystem == "com.seanking.MouseControl"'
```

The `hidpp` category logs every report in both directions at debug level. Use those captures to replace the hand-built fixtures in `Tests/MouseControlKitTests/Fixtures.swift`.

## How each feature works

- **Scroll direction**: Hi-Res Wheel `0x2121` invert bit, set when the desired mouse direction differs from the system's single "natural scrolling" setting, which the trackpad keeps. The app re-applies when that setting changes. If the device rejects the bit, an event tap negates non-continuous (wheel) scroll events instead.
- **Thumb wheel**: Thumbwheel `0x2150`, native reporting plus the invert flag.
- **DPI**: Adjustable DPI `0x2201`. The list, including step ranges, is read from the device.
- **Back/Forward**: event tap turns buttons 3/4 into ⌘[ / ⌘].
- **Thumb button**: Reprog Controls v4 `0x1B04` diverts the gesture CID after confirming it is in the device's control list and divertable. A press opens Mission Control.app, with Ctrl+↑ as the fallback.
- **Battery**: Unified Battery `0x1004`. Read on connect, polled every 5 minutes, and updated from device events.
- **Reconnect**: every device match, wake from sleep, and Wireless Device Status `0x1D4B` "reconfigure" event triggers a debounced (300 ms) re-discovery and re-apply.
