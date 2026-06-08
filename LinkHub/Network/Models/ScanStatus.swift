import Foundation

/// Story 1.3 addition; AppState mirrors WiFiMonitor.scanStatus.
enum ScanStatus: Equatable, Sendable {
    case idle
    case scanning
    case timedOut
}
