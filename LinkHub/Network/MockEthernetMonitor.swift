#if DEBUG
import Foundation
import Combine

/// Debug-only `EthernetMonitorProtocol` for previews and tests. Mirrors `MockWiFiMonitor`:
/// a settable `@Published var interfaces` seeded with representative sample interfaces so the
/// panel and `AppState` (Story 3.2) can be exercised without SystemConfiguration / real hardware.
@MainActor
final class MockEthernetMonitor: EthernetMonitorProtocol {
    /// One active adapter (link + IP + 1 Gbps) and one link-only adapter still obtaining an
    /// address. Covers the two states the panel renders differently at rest.
    static let sampleInterfaces: [EthernetInterface] = [
        EthernetInterface(
            id: "en3",
            bsdName: "en3",
            displayName: "USB 10/100/1000 LAN",
            linkSpeedMbps: 1000,
            ipv4: "192.168.1.5",
            state: .active
        ),
        EthernetInterface(
            id: "en5",
            bsdName: "en5",
            displayName: "Thunderbolt Ethernet Slot 1",
            linkSpeedMbps: 1000,
            ipv4: nil,
            state: .obtaining
        )
    ]

    @Published var interfaces: [EthernetInterface]
    var interfacesPublisher: Published<[EthernetInterface]>.Publisher { $interfaces }

    init(interfaces: [EthernetInterface] = MockEthernetMonitor.sampleInterfaces) {
        self.interfaces = interfaces
    }

    func start() {}
    func stop() {}
}
#endif
