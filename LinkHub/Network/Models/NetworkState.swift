import Foundation

struct NetworkState: Equatable, Sendable {
    let mode: ConnectionMode
    let ethernetInterfaces: [EthernetInterface]
    let primaryEthernet: EthernetInterface?
    let wifiNetworks: [WiFiNetwork]
    let connectedWifi: WiFiNetwork?
    let isWiFiEnabled: Bool
    let isWiFiHardwareAvailable: Bool

    static let empty = NetworkState(
        mode: .disconnected,
        ethernetInterfaces: [],
        primaryEthernet: nil,
        wifiNetworks: [],
        connectedWifi: nil,
        isWiFiEnabled: true,
        isWiFiHardwareAvailable: true
    )
}
