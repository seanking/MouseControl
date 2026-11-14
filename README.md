# Mouse Control

A native macOS menu-bar app for configuring a Logitech MX Master 3S and an Apple Magic Mouse. The menu shows each connected mouse with its battery and only the options that mouse supports.

## Features

### MX Master 3S

- **Scroll direction** for the mouse only, independent of the trackpad's natural scrolling.
- **Thumb wheel direction**: normal or inverted.
- **Pointer speed (DPI)** across every value the mouse supports.
- **Back/Forward buttons** that send ⌘[ and ⌘], so they work in Safari.
- **Thumb button** actions: Mission Control, App Exposé, Show Desktop, Spotlight, Notification Center, or none.
- **Drag to switch Spaces**: hold the thumb button and drag left or right.
- Works over Bluetooth or a Logi Bolt receiver.

### Magic Mouse

- **Tracking speed** up to 10. System Settings stops at 3.

### Both

- **Battery level** in the menu, and optionally in the menu bar.
- **Low battery notification** at a threshold you choose.
- **Launch at login.**
- Settings are re-applied when a mouse reconnects or the Mac wakes from sleep.

## Install

1. Download the latest release from [Releases](https://github.com/seanking/MouseControl/releases), unzip it, and move **Mouse Control** to Applications. Releases are signed with a Developer ID and notarized.
2. Quit Logi Options+ or any other mouse utility that customizes the MX Master. They divert the same controls.
3. Grant the permissions the menu asks for:
   - **Input Monitoring**, to talk to the MX Master. macOS may need a relaunch afterward; the menu offers one.
   - **Accessibility**, for Back/Forward and the thumb button.

   The Magic Mouse needs no permissions.

Mouse Control adds itself as a login item on first launch. Turn it off in the menu if you prefer.

Requires macOS 27.

## Build from source

To sign the app, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your `DEVELOPMENT_TEAM`. Git ignores that file, so your team ID stays out of the repo.

```bash
xcodebuild -project MouseControl.xcodeproj -scheme MouseControl build
swift test --package-path Packages/MouseControlKit
```

To make a release, archive in Xcode (Product › Archive) and distribute it from the Organizer with Direct Distribution, which signs and notarizes the app.

## Project layout

| Path | What |
|---|---|
| `App/` | SwiftUI `MenuBarExtra`, `DeviceController` and the per-device models (`LogitechMouse`, `MagicMouse`), `EventTapService`, settings, permissions |
| `Packages/MouseControlKit/` | HID++ 2.0 framing and features, the `IOHIDManager` transport, IORegistry device monitoring, and tracking speed. No AppKit dependency, so it can be tested without hardware. |
| `MouseControl.xcodeproj` | Xcode project (app target, scheme, signing) |
| `Config/` | `Signing.xcconfig`, which includes the git-ignored `Local.xcconfig` that holds your team ID |

## How it works

Each supported kind of mouse is a `MouseDevice` (`LogitechMouse`, `MagicMouse`) that owns its own discovery and settings. `DeviceController` coordinates them and forwards wake and permission events. The menu shows a section for each connected mouse.

### MX Master 3S (HID++ 2.0)

- **Scroll direction**: Hi-Res Wheel `0x2121` invert bit, set when the desired mouse direction differs from the system's single "natural scrolling" setting, which the trackpad keeps. The app re-applies when that setting changes. If the device rejects the bit, an event tap negates non-continuous (wheel) scroll events instead.
- **Thumb wheel**: Thumbwheel `0x2150`, native reporting plus the invert flag.
- **DPI**: Adjustable DPI `0x2201`. The list, including step ranges, is read from the device.
- **Back/Forward**: an event tap turns buttons 3/4 into ⌘[ / ⌘].
- **Thumb button**: Reprog Controls v4 `0x1B04` diverts the gesture CID after confirming it is in the device's control list and divertable. A press runs the chosen action. Mission Control launches Mission Control.app, with Ctrl+↑ as the fallback. App Exposé (⌃↓), Show Desktop (F11) and Spotlight (⌘Space) post the default system shortcuts, so they only work while those shortcuts are enabled. Notification Center presses the menu bar clock through the Accessibility API. Choosing None leaves the button undiverted.
- **Drag to switch Spaces**: the gesture button is also diverted with raw XY reporting, so while it's held the mouse sends pointer motion over HID++ instead of moving the cursor. Every ⅛ inch of horizontal drag (scaled by the current DPI) posts ⌃← or ⌃→. The click action then runs on release, and only if the button barely moved.
- **Battery**: Unified Battery `0x1004`. Read on connect, polled every 5 minutes, and updated from device events.
- **Reconnect**: every device match, wake from sleep, and Wireless Device Status `0x1D4B` "reconfigure" event triggers a debounced (300 ms) re-discovery and re-apply.

### Magic Mouse

- **Detection**: the IORegistry is watched for the mouse's pointer collection without opening it, so no permission is needed.
- **Battery**: read from the `BatteryPercent` property macOS publishes on the mouse's HID event service, every 5 minutes.
- **Tracking speed**: applied when the mouse connects and after waking from sleep, the same way as `defaults write -g com.apple.mouse.scaling -float 5.0` (persisted) plus `hidutil property --set '{"HIDMouseAcceleration":327680}'` (immediate, 16.16 fixed point). Both are system-wide, so the speed also applies to other mice.

## Debugging

```bash
log stream --level debug --predicate 'subsystem == "com.seanking.MouseControl"'
```

The `hidpp` category logs every report in both directions at debug level. Use those captures to replace the hand-built fixtures in `Packages/MouseControlKit/Tests/MouseControlKitTests/Fixtures.swift`.

## License

MIT. See [LICENSE](LICENSE).
