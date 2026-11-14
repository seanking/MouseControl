import MouseControlKit

/// One kind of mouse the app can configure. Each kind owns its own discovery and settings;
/// the menu shows a section for each connected kind with only the options that kind supports.
@MainActor
protocol MouseDevice: AnyObject {
    var isConnected: Bool { get }
    /// The connected mouse's name, as it describes itself.
    var name: String { get }
    var battery: BatteryStatus? { get }

    /// Begins watching for the device. Called once at launch.
    func start()
    /// Re-applies settings the system may have reset while asleep.
    func didWake()
}
