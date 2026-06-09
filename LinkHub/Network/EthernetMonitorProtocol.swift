// Story 3.1 surface: observation only. The dual-monitor `AppState` sink that consumes
// `interfacesPublisher` is wired in Story 3.2; this protocol exists now so 3.2 (and tests /
// previews) can depend on the seam without importing SystemConfiguration.

import Foundation
import Combine

@MainActor
protocol EthernetMonitorProtocol: AnyObject {
    /// Current snapshot of all detected Ethernet interfaces, sorted by `AppState` before display.
    var interfaces: [EthernetInterface] { get }
    var interfacesPublisher: Published<[EthernetInterface]>.Publisher { get }

    /// Starts SCDynamicStore observation and performs initial enumeration. Idempotent.
    func start()

    /// Stops SCDynamicStore observation and clears the interface list.
    func stop()
}
