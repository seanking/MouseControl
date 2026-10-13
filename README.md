# MouseControl

A native macOS 27 menu-bar app that replaces the parts of Logi Options+ used with an MX Master 3S: mouse-only scroll direction, thumb-wheel direction, DPI, Back/Forward in Safari, thumb button → Mission Control, and battery.

## Layout

| Path | What |
|---|---|
| `App/` | SwiftUI `MenuBarExtra`, `DeviceController`, `EventTapService`, settings, permissions |
| `Packages/MouseControlKit/` | HID++ 2.0 framing/matching (`HIDPPChannel`), features, `IOHIDManager` transport. No AppKit dependency, so it can be tested without hardware. |
| `MouseControl.xcodeproj` | Xcode project (app target, scheme, signing) |
| `Config/` | `Signing.xcconfig`, which includes the git-ignored `Local.xcconfig` that holds your team ID |
| `Scripts/release.sh` | Archive → Developer ID sign → notarize → staple |

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

Logi Options+ has no bundled uninstaller, and moving `logioptionsplus.app` to the Trash leaves its background agent and updater running. Remove it completely before using MouseControl.

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
- **Thumb button**: Reprog Controls v4 `0x1B04` diverts the gesture CID after confirming it is in the device's control list and divertable. A press opens Mission Control.app, with Ctrl+↑ as the fallback.
- **Battery**: Unified Battery `0x1004`. Read on connect, polled every 5 minutes, and updated from device events.
- **Reconnect**: every device match, wake from sleep, and Wireless Device Status `0x1D4B` "reconfigure" event triggers a debounced (300 ms) re-discovery and re-apply.
