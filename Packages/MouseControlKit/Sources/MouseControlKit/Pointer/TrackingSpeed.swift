import Foundation
import IOKit.hidsystem

/// The system mouse tracking speed, set the same way as
/// `defaults write -g com.apple.mouse.scaling -float <speed>` (persisted, applied at login) plus
/// `hidutil property --set '{"HIDMouseAcceleration":<speed × 65536>}'` (applied immediately).
/// Both are system-wide: they affect every mouse, not only the one that prompted the change.
public enum TrackingSpeed {
    static let preferenceKey = "com.apple.mouse.scaling"
    static let hidKey = "HIDMouseAcceleration"

    /// System Settings stops at 3; larger values are only reachable from the command line.
    public static let range: ClosedRange<Double> = 0...10
    public static let step = 0.25

    /// `HIDMouseAcceleration` is 16.16 fixed point: 5.0 → 327680.
    public static func fixedPoint(_ speed: Double) -> Int {
        Int((speed * 65536).rounded())
    }

    /// Clamps to `range` and rounds to the nearest `step`.
    public static func snap(_ speed: Double) -> Double {
        ((min(max(speed, range.lowerBound), range.upperBound)) / step).rounded() * step
    }

    /// The persisted speed, or nil if it has never been changed from the system default.
    public static var current: Double? {
        (CFPreferencesCopyValue(preferenceKey as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber)?.doubleValue
    }

    /// Returns false if the HID event system rejected the live value.
    @discardableResult
    public static func apply(_ speed: Double) -> Bool {
        CFPreferencesSetValue(preferenceKey as CFString, speed as CFNumber, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        return IOHIDEventSystemClientSetProperty(client, hidKey as CFString, fixedPoint(speed) as CFNumber)
    }
}
