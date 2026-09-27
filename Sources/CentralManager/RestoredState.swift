//  Added by emotiveapps. Not in upstream AsyncBluetooth.

import CoreBluetooth
import Foundation

/// The state iOS hands back when it relaunches the app for a Bluetooth event, kept until asked for.
///
/// `centralManager(_:willRestoreState:)` arrives while the central manager is still being set up,
/// before anything has had a chance to subscribe to `eventPublisher`, whose subject keeps nothing
/// for a late subscriber. So the event alone is easy to miss, and it is the one that says which
/// peripherals the app was holding when the system ended it. This keeps a copy.
final class RestoredStateBox: @unchecked Sendable {
    // `@unchecked`: every access is under `lock`. The dictionary is CoreBluetooth's, read-only here.
    private let lock = NSLock()
    private var state: [String: Any]?

    var value: [String: Any]? { lock.withLock { state } }

    func keep(_ restored: [String: Any]) { lock.withLock { state = restored } }
}

extension CentralManager {
    /// What iOS restored when it relaunched this app for Bluetooth, or nil if this launch was not
    /// one of those (or the central manager was built without a restore identifier).
    ///
    /// The same dictionary `willRestoreState` carries on `eventPublisher`, for a caller that
    /// subscribed too late to see that event.
    public var restoredState: [String: Any]? { restoredStateBox.value }

    /// The peripherals iOS was holding for this app when it ended it, from `restoredState`.
    public var restoredPeripherals: [Peripheral] {
        let restored = restoredState?[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        return restored.map { Peripheral($0) }
    }
}
