import Foundation

/// Placeholder type so `NetworkState.ethernetInterfaces` can compile in Story 1.3.
/// Story 3.1 wires the real producer (`EthernetMonitor` via SCDynamicStore).
struct EthernetInterface: Identifiable, Equatable, Sendable {
    let id: String
    let bsdName: String
    let displayName: String
    let isActive: Bool
    let linkSpeedMbps: Int?
}
