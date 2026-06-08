import Foundation

/// Sendable Wi-Fi network value extracted from CoreWLAN at the monitor boundary.
/// `id` falls back to `"\(ssid ?? "hidden"):\(security)"` when bssid is nil
/// (hidden networks or location-permission-denied scans).
struct WiFiNetwork: Identifiable, Equatable, Sendable {
    let id: String
    let ssid: String?
    let bssid: String?
    let rssi: Int
    let isConnected: Bool
    let requiresPassword: Bool
    let security: WiFiSecurity
    let isCaptive: Bool
}
