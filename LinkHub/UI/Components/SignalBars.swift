import SwiftUI

/// 4-bar Wi-Fi signal-strength indicator.
///
/// Renders custom `RoundedRectangle` bars (PRD 04 D6) rather than SF Symbols:
/// the canonical 4-level Wi-Fi SF Symbol set (`wifi.0`…`wifi.3`) is macOS 14+ / iOS-only,
/// and LinkHub's deployment floor is macOS 13.0. Decorative — `.accessibilityHidden(true)`;
/// signal strength is conveyed in the row's combined accessibility label (UX-DR22).
struct SignalBars: View {
    let rssi: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(idx < Self.activeBars(for: rssi) ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: 2.5, height: CGFloat(4 + idx * 3))   // 4, 7, 10, 13 pt
            }
        }
        .frame(width: PanelLayout.signalBarsSize, height: PanelLayout.signalBarsSize, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }

    /// RSSI (dBm) → active bar count. Buckets must agree with
    /// `WiFiRow.signalStrengthDescription(for:)`. See Story 1.4 RSSI mapping table.
    static func activeBars(for rssi: Int) -> Int {
        switch rssi {
        case let r where r >= -60: return 4
        case let r where r >= -70: return 3
        case let r where r >= -80: return 2
        default: return 1
        }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 12) {
        SignalBars(rssi: -50)   // excellent → 4 bars
        SignalBars(rssi: -65)   // good → 3 bars
        SignalBars(rssi: -75)   // fair → 2 bars
        SignalBars(rssi: -85)   // weak → 1 bar
    }
    .padding()
}
#endif
