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

    /// Canonical RSSI (dBm) → human signal-strength descriptor (UX signal-quality table).
    /// Single source of truth shared by the panel rows (`WiFiRow`) and the menu-bar icon
    /// accessibility label (`StatusItemController`). Buckets must agree with
    /// `SignalBars.activeBars(for:)`.
    static func signalStrengthDescription(for rssi: Int) -> String {
        switch rssi {
        case let r where r >= -60: return "excellent"
        case let r where r >= -70: return "good"
        case let r where r >= -80: return "fair"
        default: return "weak"
        }
    }
}
