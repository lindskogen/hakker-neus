import Network
import os

/// Whether the connection is cheap enough to fetch things the user may never open
/// (comments for the rows on screen): not cellular or a hotspot, and not Low Data Mode.
final class NetworkConditions: Sendable {
    static let shared = NetworkConditions()

    private let monitor = NWPathMonitor()
    private let unmetered = OSAllocatedUnfairLock(initialState: false)

    var allowsSpeculativeFetching: Bool { unmetered.withLock { $0 } }

    private init() {
        monitor.pathUpdateHandler = { [unmetered] path in
            unmetered.withLock { $0 = path.status == .satisfied && !path.isExpensive && !path.isConstrained }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkConditions", qos: .utility))
    }
}
