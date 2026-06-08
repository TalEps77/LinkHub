import Foundation

/// Cause-typed Wi-Fi connection failure (FR37). The Network layer maps the opaque
/// `CWErrorDomain` code thrown by `CWInterface.associate(to:password:)` into this enum so the
/// UI (Story 2.3) can render a specific, actionable message instead of a raw `NSError`.
///
/// `import Foundation` only — the Models layer never imports CoreWLAN. The
/// `CWErrorDomain` → `WiFiConnectionFailure` mapping is a pure static function that takes the
/// already-extracted integer error code, keeping this file CoreWLAN-free and unit-testable
/// without live hardware. The `WiFiMonitor` (which imports CoreWLAN) extracts
/// `(error as NSError).code` at the boundary and calls `map(cwErrorCode:)`.
enum WiFiConnectionFailure: Error, Equatable, Sendable {
    /// PSK association rejected — typically an incorrect passphrase. Recognized at the live
    /// boundary via the symbolic `CWError.Code.notPermitted` (no dedicated numeric `CWErr`
    /// constant exists — see `WiFiMonitor.failure(from:)`).
    case wrongPassword
    /// The target network is not reachable / out of range. (`kCWUnsupportedCapabilitiesErr`,
    /// `kCWUnspecifiedFailureErr`, or no matching `CWNetwork` in scan results.)
    case outOfRange
    /// The association or device handshake did not complete in time. (`kCWTimeoutErr`,
    /// `kCWDeviceTimeoutErr`)
    case associationTimeout
    /// An EAPOL / 802.1X authentication exchange failed. (`kCWEAPOLErr`)
    case authenticationError
    /// Any other `CWErrorDomain` code — carries the raw value so logs/UI can still report it.
    case unknown(code: Int)

    /// Pure, static, hardware-free mapping of a `CWErrorDomain` integer code (the value of
    /// `(error as NSError).code` for a `CWError`) to a cause-typed failure. The integer values are
    /// the canonical `CWErr` constants from `<CoreWLAN/CWError.h>` — they are stable across the
    /// macOS versions LinkHub targets (13+). Anything unrecognized falls through to
    /// `.unknown(code:)` so no failure is ever silently swallowed.
    ///
    /// This `Int` overload is the unit-testable contract (the Models layer is Foundation-only and
    /// never imports CoreWLAN). At the live boundary, `WiFiMonitor.performAssociate` switches on
    /// the strongly-typed `CWError.Code` enum *first* (symbolic names, version-robust) and only
    /// falls back to feeding `(error as NSError).code` here for non-`CWError` / unrecognized
    /// `NSError`s — so the magic numbers below back up, rather than gate, the live path.
    ///
    /// | `CWErrorDomain` code | `CWErr` constant | → case |
    /// |---|---|---|
    /// | -3905 | `kCWTimeoutErr` | `.associationTimeout` |
    /// | -3908 | `kCWDeviceTimeoutErr` | `.associationTimeout` |
    /// | 1 | `kCWEAPOLErr` | `.authenticationError` |
    /// | -3907 | `kCWUnsupportedCapabilitiesErr` | `.outOfRange` |
    /// | -3906 | `kCWUnspecifiedFailureErr` | `.outOfRange` |
    /// | -3903 | `kCWNotSupportedErr` | `.outOfRange` |
    /// | (any other) | — | `.unknown(code:)` |
    ///
    /// Note on wrong-password: CoreWLAN does NOT expose a dedicated numeric constant for "PSK
    /// rejected"; an incorrect passphrase typically surfaces as the modern `CWError.Code` case
    /// `.notPermitted` (whose raw value is not pinned across SDKs) or as a timeout. The
    /// `.wrongPassword` mapping is therefore driven by the symbolic `CWError.Code` switch in
    /// `WiFiMonitor`, not by a hard-coded integer here — see that file's `performAssociate`.
    static func map(cwErrorCode: Int) -> WiFiConnectionFailure {
        switch cwErrorCode {
        case -3905, -3908:
            // kCWTimeoutErr / kCWDeviceTimeoutErr — association handshake stalled.
            return .associationTimeout
        case 1:
            // kCWEAPOLErr — 802.1X / EAPOL exchange failed.
            return .authenticationError
        case -3907, -3906, -3903:
            // kCWUnsupportedCapabilitiesErr / kCWUnspecifiedFailureErr / kCWNotSupportedErr — the
            // radio could not reach / complete association with the target; treat as
            // out-of-range/unavailable.
            return .outOfRange
        default:
            return .unknown(code: cwErrorCode)
        }
    }
}
