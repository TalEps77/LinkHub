import Foundation

/// Snapshot of a single Ethernet adapter's state. Produced by `EthernetMonitor` (Story 3.1)
/// from SystemConfiguration reads, consumed by `AppState` and the panel UI. Foundation-only
/// `Sendable` value type — it crosses the SCDynamicStore-queue → MainActor boundary as the
/// only payload (no `SCNetworkInterface`/`CFType` ever crosses; NFR8).
struct EthernetInterface: Identifiable, Equatable, Sendable {
    /// BSD interface name, e.g. "en3". Stable identity for the duration of a session.
    let id: String

    /// BSD interface name (same value as `id`). Kept as a named field for call-site clarity
    /// where the interface name is the intent rather than diffing identity.
    let bsdName: String

    /// Human-readable display name from `SCNetworkInterfaceGetLocalizedDisplayName`,
    /// e.g. "USB 10/100/1000 LAN" or "Thunderbolt Ethernet Slot 1". Falls back to `bsdName`
    /// when the localized name is unavailable.
    let displayName: String

    /// Negotiated link speed in megabits per second (e.g. 100, 1000, 2500, 10000).
    /// `nil` when the interface has no link or the speed cannot be determined
    /// (read via `SCNetworkInterfaceCopyMediaOptions`; PRD 05 Decision #1).
    let linkSpeedMbps: Int?

    /// Primary IPv4 address, `nil` until DHCP / manual assignment completes.
    let ipv4: String?

    /// Derived interface state (FR16). See `EthernetInterfaceState`.
    let state: EthernetInterfaceState

    /// `true` when the interface has a link (cable in) AND an assigned IP address.
    /// Computed from `state` so the existing `AppState.computeConnectionMode` API is preserved
    /// (`ethernet.contains(where: \.isActive)` → `.ethernetActive`). Link-only / obtaining /
    /// timeout interfaces are NOT active and do not flip the menu-bar icon.
    var isActive: Bool { state == .active }
}

/// The four wired-interface states surfaced to the panel (FR16). Foundation-only `Sendable`.
///
/// Derived from two physical signals — physical link (cable in) and IPv4 assignment — plus a
/// presentation-supplied DHCP-timeout flag (the 30 s clock lives in the UI layer per PRD 05
/// Decision #11; the monitor only knows link + IP at read time, so the live path always
/// produces `.active` / `.obtaining` / `.noLink` and the UI re-derives `.dhcpTimeout`).
enum EthernetInterfaceState: Equatable, Sendable {
    /// Cable in, IPv4 assigned. Drives `ConnectionMode.ethernetActive`.
    case active
    /// Cable in, no IPv4 yet (DHCP in progress, within the timeout window).
    case obtaining
    /// Cable in, no IPv4 after the DHCP timeout window elapsed (UI-derived).
    case dhcpTimeout
    /// No physical link (cable out).
    case noLink
}
