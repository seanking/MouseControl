import Foundation
import MouseControlKit
import UserNotifications

/// Posts one low-battery notification per discharge cycle.
@MainActor
final class BatteryNotifier {
    private var warned = false

    /// `threshold` is the warning percentage; 0 disables notifications.
    func update(_ status: BatteryStatus, deviceName: String, threshold: Int) {
        if status.charging.isCharging || status.percentage > threshold + 5 {
            warned = false
            return
        }
        guard threshold > 0, !warned, status.percentage <= threshold else { return }
        warned = true

        let content = UNMutableNotificationContent()
        content.title = "\(deviceName) battery low"
        content.body = "\(status.percentage)% remaining. Charge it soon."
        let request = UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
