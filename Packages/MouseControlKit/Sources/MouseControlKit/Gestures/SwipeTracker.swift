import Foundation

/// Turns raw pointer motion reported while a button is held into horizontal swipes.
/// Create one per press, feed it every motion event, and ask `isTap` on release.
public struct SwipeTracker: Sendable {
    public enum Direction: Sendable, Equatable {
        case left, right
    }

    /// Horizontal travel, in sensor counts, that makes one swipe.
    public let threshold: Int
    /// Motion since the last swipe (or the press).
    private var dx = 0
    private var dy = 0
    /// Total motion since the press, used to tell a tap from an abandoned drag.
    private var travel = 0
    public private(set) var swipeCount = 0

    public init(threshold: Int) {
        self.threshold = max(threshold, 1)
    }

    /// Sensor counts for a physical distance at the mouse's current DPI.
    public static func threshold(inches: Double, dpi: Int?) -> Int {
        Int((Double(dpi ?? 1000) * inches).rounded())
    }

    /// Adds motion and returns a direction each time horizontal travel crosses the threshold,
    /// so one long drag can move several spaces.
    public mutating func add(dx: Int, dy: Int) -> Direction? {
        self.dx += dx
        self.dy += dy
        travel += abs(dx) + abs(dy)
        guard abs(self.dx) >= threshold, abs(self.dx) > abs(self.dy) else { return nil }
        let direction: Direction = self.dx > 0 ? .right : .left
        self.dx = 0
        self.dy = 0
        swipeCount += 1
        return direction
    }

    /// The press was a click: no swipe and barely any motion.
    public var isTap: Bool {
        swipeCount == 0 && travel < threshold / 2
    }
}
