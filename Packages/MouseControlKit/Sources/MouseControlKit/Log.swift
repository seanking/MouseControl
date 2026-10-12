import Foundation
import os

/// Loggers share the host app's bundle identifier as subsystem so `log stream --predicate` finds everything.
public enum Log {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "MouseControl"

    public static let transport = Logger(subsystem: subsystem, category: "transport")
    /// Raw report traffic at `.debug` level (not persisted). Useful for capturing test fixtures:
    /// `log stream --level debug --predicate 'category == "hidpp"'`
    public static let hidpp = Logger(subsystem: subsystem, category: "hidpp")
    public static let device = Logger(subsystem: subsystem, category: "device")
}
