# Mouse Control

A native macOS 27 menu-bar app that replaces the parts of Logi Options+ used with an MX Master 3S: mouse-only scroll direction, thumb-wheel direction, DPI, Back/Forward in Safari, a configurable thumb button (Mission Control, App Exposé, Show Desktop, Spotlight, Notification Center, or drag to switch Spaces), and battery. It also sets the tracking speed while an Apple Magic Mouse is connected.

## Layout

| Path | What |
|---|---|
| `App/` | SwiftUI `MenuBarExtra`, `DeviceController` and the per-device models (`LogitechMouse`, `MagicMouse`), `EventTapService`, settings, permissions |
| `Packages/MouseControlKit/` | HID++ 2.0 framing/matching (`HIDPPChannel`), features, `IOHIDManager` transport. No AppKit dependency, so it can be tested without hardware. |
| `MouseControl.xcodeproj` | Xcode project (app target, scheme, signing) |
| `Config/` | `Signing.xcconfig`, which includes the git-ignored `Local.xcconfig` that holds your team ID |

## Build & test

To sign the app, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your `DEVELOPMENT_TEAM`. Git ignores that file, so your team ID stays out of the repo.

```bash
xcodebuild -project MouseControl.xcodeproj -scheme MouseControl build
swift test --package-path Packages/MouseControlKit
```

## First run

1. Quit and uninstall Logi Options+; it diverts the same controls. See [Uninstalling Logi Options+](#uninstalling-logi-options).
2. Grant **Input Monitoring** (opens the mouse's HID++ channel) and **Accessibility** (event tap and key posting). The menu links to both panes. macOS may require a relaunch after granting Input Monitoring; the menu offers it.
3. The app registers itself as a login item on first launch.

## Uninstalling Logi Options+

Logi Options+ has no bundled uninstaller, and moving `logioptionsplus.app` to the Trash leaves its background agent and updater running. Remove it completely before using Mouse Control.

1. Quit Logi Options+, then unload and stop its background services:

   ```bash
   sudo launchctl bootout system /Library/LaunchDaemons/com.logi.optionsplus.updater.plist
   launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.logi.optionsplus.plist
   killall logioptionsplus_agent logioptionsplus_updater LogiPluginService 2>/dev/null
   ```

2. Delete the app and its system-wide files:

   ```bash
   sudo rm -rf /Applications/logioptionsplus.app \
     /Applications/Utilities/LogiPluginService.app \
     "/Applications/Utilities/Logi Options+ Driver Installer.bundle" \
     "/Library/Application Support/Logitech.localized/LogiOptionsPlus" \
     "/Library/Application Support/Logi" \
     /Library/LaunchAgents/com.logi.optionsplus.plist \
     /Library/LaunchDaemons/com.logi.optionsplus.updater.plist
   ```

3. Optionally, delete your user settings:

   ```bash
   rm -rf ~/Library/Application\ Support/LogiOptionsPlus \
     ~/Library/Application\ Support/Logi \
     ~/Library/Preferences/com.logi.optionsplus*.plist \
     ~/Library/Preferences/com.logi.pluginservice.plist
   ```

4. If the older **Logitech Options** is also installed, run `/Applications/Utilities/LogiMgr Uninstaller.app`. It diverts the same controls.

5. In **System Settings → Privacy & Security**, remove any remaining Logi entries from **Input Monitoring**, **Accessibility**, and **Bluetooth**. In **General → Login Items & Extensions**, remove any remaining Logi items.

6. Restart the Mac so no process still holds the mouse's HID++ channel.

Paths can vary between Options+ versions; any entry that doesn't exist can be skipped. Other Logitech software, such as webcam utilities, can stay installed.

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
- **Thumb button**: Reprog Controls v4 `0x1B04` diverts the gesture CID after confirming it is in the device's control list and divertable. A press runs the chosen action. Mission Control launches Mission Control.app, with Ctrl+↑ as the fallback. App Exposé (⌃↓), Show Desktop (F11) and Spotlight (⌘Space) post the default system shortcuts, so they only work while those shortcuts are enabled. Notification Center presses the menu bar clock through the Accessibility API. Choosing None leaves the button undiverted.
- **Drag to switch Spaces**: the gesture button is also diverted with raw XY reporting, so while it's held the mouse sends pointer motion over HID++ instead of moving the cursor. Every ⅛ inch of horizontal drag (scaled by the current DPI) posts ⌃← or ⌃→. The click action then runs on release, and only if the button barely moved.
- **Per-device menu**: each supported kind of mouse is a `MouseDevice` (`LogitechMouse`, `MagicMouse`) that owns its own discovery and settings. `DeviceController` coordinates them and forwards wake and permission events. The menu shows a section for each connected mouse, with its name, battery, and only the options it supports.
- **Magic Mouse**: the IORegistry is watched for its pointer collection without opening it, so it needs no permission. Battery comes from the `BatteryPercent` property macOS publishes on its HID event service. When the mouse connects, and after waking from sleep, the chosen tracking speed is applied the same way as `defaults write -g com.apple.mouse.scaling -float 5.0` (persisted) plus `hidutil property --set '{"HIDMouseAcceleration":327680}'` (immediate, 16.16 fixed point). Both are system-wide, so the speed also applies to other mice. The slider goes to 10; System Settings stops at 3.
- **Battery**: Unified Battery `0x1004`. Read on connect, polled every 5 minutes, and updated from device events.
- **Reconnect**: every device match, wake from sleep, and Wireless Device Status `0x1D4B` "reconfigure" event triggers a debounced (300 ms) re-discovery and re-apply.

## License

MIT. See [LICENSE](LICENSE).
