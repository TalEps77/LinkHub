// Story 2.1 adds `connect(to:password:remember:)`, `disconnect()`, and the typed
// `WiFiConnectionFailure` error path. Do not add them now — out of scope for Story 1.3.

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
}
