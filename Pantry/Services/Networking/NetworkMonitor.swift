import Foundation
import Network
import Observation

/// Tracks reachability so the app can say "you're offline" instead of letting a request
/// time out and look broken.
@Observable
final class NetworkMonitor {

    private(set) var isConnected: Bool = true
    private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.pantryapp.Pantry.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor [weak self] in
                self?.isConnected = connected
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
