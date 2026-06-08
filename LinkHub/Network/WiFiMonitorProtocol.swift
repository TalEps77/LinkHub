// Story 2.1 adds `associate(network:password:)` returning the typed `WiFiConnectionFailure`
// error path. Keychain persistence (Story 2.2), `disconnect()` / captive handling (Story 2.5),
// and power toggle (Story 2.5) are still out of scope.

import Foundation
import Combine

@MainActor
protocol WiFiMonitorProtocol: AnyObject {
    var networks: [WiFiNetwork] { get }
    var networksPublisher: Published<[WiFiNetwork]>.Publisher { get }

    var connectedNetwork: WiFiNetwork? { get }
    var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { get }

    var isEnabled: Bool { get }
    var isEnabledPublisher: Published<Bool>.Publisher { get }

    var isHardwareAvailable: Bool { get }
    var isHardwareAvailablePublisher: Published<Bool>.Publisher { get }

    var scanStatus: ScanStatus { get }
    var scanStatusPublisher: Published<ScanStatus>.Publisher { get }

    /// `true` when CoreLocation authorization is `.denied` / `.restricted`. Exposed as a plain
    /// `Bool` so no CoreLocation type crosses the protocol boundary (Story 1.5). The real
    /// monitor drives it from `CLLocationManager`; the mock sets it directly.
    var isLocationDenied: Bool { get }
    var isLocationDeniedPublisher: Published<Bool>.Publisher { get }

    func start()
    func stop()
    func requestScan() async

    /// Attempts to associate with `network`. When `password == nil` the open variant is used.
    /// Runs the blocking `CWInterface.associate(to:password:)` off the MainActor and returns a
    /// cause-typed `Result` (FR29) — no `NSError` ever crosses this boundary (UX-DR30). On
    /// completion (success or failure) the monitor is left in a clean, retryable state (NFR10).
    /// UI rendering of the failure is Story 2.3; this method only delivers the typed contract.
    func associate(network: WiFiNetwork, password: String?) async -> Result<Void, WiFiConnectionFailure>
}
