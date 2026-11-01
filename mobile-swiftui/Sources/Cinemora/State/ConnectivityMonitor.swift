import Foundation
import Observation
import Network

@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isConnected = true
    /// NWPathMonitor reports asynchronously. Keep the optimistic launch value
    /// from briefly covering the app before the first path is known.
    private(set) var hasDeterminedStatus = false

    var isOffline: Bool {
        hasDeterminedStatus && !isConnected
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cinemora.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.hasDeterminedStatus = true
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
