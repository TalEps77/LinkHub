import SwiftUI

/// A single Ethernet-interface row (Story 3.3, FR16).
///
/// Anatomy (UX-DR11): `HStack { StateDot; VStack(.leading) { displayName(.body); detail(.caption) } }`.
/// The state is conveyed by BOTH an 8 pt color dot AND a plain-text status label so color is never
/// the only signal (UX-DR26); the decorative dot is `.accessibilityHidden(true)` and the row exposes
/// one combined label.
///
/// Four states (FR16) map to (label, dot color, detail) via the pure static helpers below:
/// - `.active(ip, speed)` → "Active", green dot, detail `"{ip} • {speed}"`
/// - `.obtaining`         → "Obtaining…", yellow dot (pulsing when Reduce Motion is off, UX-DR19/20)
/// - `.dhcpTimeout`       → "DHCP timeout", red dot
/// - `.noLink`            → "No link", gray (`.secondary`) dot
///
/// Imports `SwiftUI` only; reads no monitor. Semantic ShapeStyles only — the status-dot colors
/// (`.green`/`.yellow`/`.red`/`.secondary`) are the documented exception to "semantic only", and
/// `Color.red` is allowed solely for the DHCP-timeout label's inline text (UX-DR4).
struct EthernetRow: View {
    let interface: EthernetInterface

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    /// Drives the `.obtaining` pulse. Local view state — flipped on appear so the
    /// `.repeatForever` animation has two endpoints to interpolate between (0.4 ↔ 1.0).
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            stateDot
            VStack(alignment: .leading, spacing: 1) {
                Text(interface.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                detailText
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PanelLayout.rowVerticalPadding)
        .padding(.horizontal, PanelLayout.rowHorizontalPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: interface))
    }

    // MARK: - State dot

    /// 8 pt circle tinted by state (UX-DR26). The `.obtaining` dot pulses opacity 0.4 → 1.0 on a
    /// 1.2 s ease-in-out loop when Reduce Motion is off, and stays static at 1.0 when on (UX-DR19/20).
    private var stateDot: some View {
        let isObtaining = interface.state == .obtaining
        return Circle()
            .fill(Self.dotColor(for: interface.state))
            .frame(width: 8, height: 8)
            .opacity(isObtaining && !reduceMotion ? (pulsing ? 1.0 : 0.4) : 1.0)
            .animation(
                isObtaining && !reduceMotion
                    ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                    : nil,
                value: pulsing
            )
            .onAppear { if isObtaining && !reduceMotion { pulsing = true } }
            .accessibilityHidden(true)
    }

    // MARK: - Detail line

    /// The `.caption`/`.secondary` second line. The DHCP-timeout label is the one place a literal
    /// `Color.red` is allowed for inline text (UX-DR4); every other state uses `.secondary`.
    @ViewBuilder
    private var detailText: some View {
        let detail = Self.detailString(for: interface)
        if interface.state == .dhcpTimeout {
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.red)
        } else {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pure, testable helpers

    /// Short status label for the state — the plain-text half of the dot+label pair (UX-DR26).
    static func statusLabel(for state: EthernetInterfaceState) -> String {
        switch state {
        case .active:       return "Active"
        case .obtaining:    return "Obtaining…"
        case .dhcpTimeout:  return "DHCP timeout"
        case .noLink:       return "No link"
        }
    }

    /// Status-dot ShapeStyle per state. These four colors are the documented exception to the
    /// "semantic colors only" rule for the status indicator dot.
    static func dotColor(for state: EthernetInterfaceState) -> Color {
        switch state {
        case .active:       return .green
        case .obtaining:    return .yellow
        case .dhcpTimeout:  return .red
        case .noLink:       return .secondary
        }
    }

    /// The `.caption` detail line. Active interfaces show `"{ip} • {speed}"`; the other three
    /// states surface their status label (the dot's color alone never carries meaning, UX-DR26).
    static func detailString(for interface: EthernetInterface) -> String {
        switch interface.state {
        case .active:
            let ip = interface.ipv4 ?? ""
            let speed = speedDescription(interface.linkSpeedMbps)
            switch (ip.isEmpty, speed.isEmpty) {
            case (false, false): return "\(ip) • \(speed)"
            case (false, true):  return ip
            case (true, false):  return speed
            case (true, true):   return statusLabel(for: .active)
            }
        case .obtaining:    return statusLabel(for: .obtaining)
        case .dhcpTimeout:  return statusLabel(for: .dhcpTimeout)
        case .noLink:       return statusLabel(for: .noLink)
        }
    }

    /// Negotiated link speed (Mbps) → display string: `1000 → "1.0 Gbps"`, `2500 → "2.5 Gbps"`,
    /// `100 → "100 Mbps"`, `nil → ""`. Speeds ≥ 1000 render in Gbps to one decimal place; below
    /// 1000 render in Mbps. Pure function — unit-tested directly.
    static func speedDescription(_ mbps: Int?) -> String {
        guard let mbps else { return "" }
        if mbps >= 1000 {
            let gbps = Double(mbps) / 1000.0
            return String(format: "%.1f Gbps", gbps)
        }
        return "\(mbps) Mbps"
    }

    /// Combined VoiceOver label per the canonical UX-DR23 templates (Story 3.6, FR57, NFR25):
    /// - active:      "{displayName}, active, {ip}, {speed}" ("{ip}" → "no address" if absent;
    ///                speed omitted when unknown)
    /// - obtaining:   "{displayName}, obtaining address"
    /// - dhcpTimeout: "{displayName}, DHCP timeout, no address"
    /// - noLink:      "{displayName}, no link"
    static func accessibilityLabel(for interface: EthernetInterface) -> String {
        let name = interface.displayName
        switch interface.state {
        case .active:
            let ip = interface.ipv4 ?? "no address"
            let speed = speedDescription(interface.linkSpeedMbps)
            return speed.isEmpty ? "\(name), active, \(ip)" : "\(name), active, \(ip), \(speed)"
        case .obtaining:
            return "\(name), obtaining address"
        case .dhcpTimeout:
            return "\(name), DHCP timeout, no address"
        case .noLink:
            return "\(name), no link"
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        EthernetRow(interface: EthernetInterface(id: "en3", bsdName: "en3", displayName: "USB 10/100/1000 LAN", linkSpeedMbps: 1000, ipv4: "192.168.1.5", state: .active))
        EthernetRow(interface: EthernetInterface(id: "en5", bsdName: "en5", displayName: "Thunderbolt Ethernet Slot 1", linkSpeedMbps: 1000, ipv4: nil, state: .obtaining))
        EthernetRow(interface: EthernetInterface(id: "en6", bsdName: "en6", displayName: "USB-C LAN", linkSpeedMbps: 100, ipv4: nil, state: .dhcpTimeout))
        EthernetRow(interface: EthernetInterface(id: "en7", bsdName: "en7", displayName: "USB-C Ethernet", linkSpeedMbps: nil, ipv4: nil, state: .noLink))
    }
    .frame(width: PanelLayout.panelWidth)
    .padding(.vertical)
}
#endif
