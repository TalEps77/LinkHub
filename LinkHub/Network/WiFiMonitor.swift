import Foundation
import Combine
import CoreWLAN
import CoreLocation

@MainActor
final class WiFiMonitor: NSObject, CWEventDelegate, CLLocationManagerDelegate, WiFiMonitorProtocol {
    @Published private(set) var networks: [WiFiNetwork] = []
    @Published private(set) var connectedNetwork: WiFiNetwork? = nil
    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var isHardwareAvailable: Bool = true
    @Published private(set) var scanStatus: ScanStatus = .idle
    @Published private(set) var isLocationDenied: Bool = false

    var networksPublisher: Published<[WiFiNetwork]>.Publisher { $networks }
    var connectedNetworkPublisher: Published<WiFiNetwork?>.Publisher { $connectedNetwork }
    var isEnabledPublisher: Published<Bool>.Publisher { $isEnabled }
    var isHardwareAvailablePublisher: Published<Bool>.Publisher { $isHardwareAvailable }
    var scanStatusPublisher: Published<ScanStatus>.Publisher { $scanStatus }
    var isLocationDeniedPublisher: Published<Bool>.Publisher { $isLocationDenied }

    private let eventSubject = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []
    private var inFlightScan: Task<Void, Never>? = nil
    private var isScanInFlight: Bool = false
    private var isStarted: Bool = false
    private let scanTimeoutNanoseconds: UInt64

    // CoreLocation: macOS 10.15+ requires granted Location access for CoreWLAN scanning to
    // return results (docs/08). The manager is owned and accessed on MainActor only.
    private let locationManager = CLLocationManager()
    /// `true` once `requestWhenInUseAuthorization()` has been issued, so repeat scans do not
    /// re-request (the system no-ops repeats, but we avoid log/UI noise — docs/08 D5).
    private var didRequestAuthorization = false

    #if DEBUG
    /// Test-only override for the scan body. When set, replaces the real CoreWLAN scan.
    internal var _scanOverride: (@Sendable () async throws -> [WiFiNetwork])? = nil
    /// Test-only override for the associate body. When set, replaces the real CoreWLAN
    /// `associate(to:password:)` path so `associate(network:password:)` is exercisable without
    /// live hardware. Mirrors the `_scanOverride` seam.
    internal var _associateOverride: (@Sendable (WiFiNetwork, String?) async -> Result<Void, WiFiConnectionFailure>)? = nil
    /// Test-only read of the "authorization already requested" guard (FR39). Lets a test assert
    /// that the first `requestScan()` flips this true exactly once, without a live CLLocationManager.
    internal var _didRequestAuthorizationForTesting: Bool { didRequestAuthorization }
    #endif

    init(scanTimeoutNanoseconds: UInt64 = 5_000_000_000) {
        self.scanTimeoutNanoseconds = scanTimeoutNanoseconds
        super.init()
        locationManager.delegate = self
        // Seed from current authorization so a previously-denied state shows the denial view
        // immediately on launch (before any scan is requested).
        isLocationDenied = Self.isDenied(locationManager.authorizationStatus)
    }

    func start() {
        guard !isStarted else { return }
        guard let iface = CWWiFiClient.shared().interface() else {
            isHardwareAvailable = false
            isEnabled = false
            isStarted = true
            return
        }
        isHardwareAvailable = true
        isEnabled = iface.powerOn()

        let client = CWWiFiClient.shared()
        client.delegate = self
        var registered = 0
        for event in [CWEventType.ssidDidChange, .linkDidChange, .linkQualityDidChange, .powerDidChange] {
            do {
                try client.startMonitoringEvent(with: event)
                registered += 1
            } catch {
                Log.networkWiFi.error("CWWiFiClient.startMonitoringEvent failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if registered == 0 {
            // All event registrations failed — surface degraded state instead of staying silent.
            Log.networkWiFi.error("All CWEventDelegate registrations failed; marking hardware unavailable")
            isHardwareAvailable = false
        }

        connectedNetwork = Self.makeConnectedNetwork(from: iface, isEnabled: isEnabled)

        eventSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshFromCurrentInterface()
                }
            }
            .store(in: &cancellables)
        isStarted = true
    }

    func stop() {
        CWWiFiClient.shared().delegate = nil
        cancellables.removeAll()
        inFlightScan?.cancel()
        inFlightScan = nil
        isScanInFlight = false
        networks = []
        connectedNetwork = nil
        // Reset to "no Wi-Fi" rather than the optimistic default — subscribers must not see
        // "Wi-Fi enabled" lies during teardown.
        isEnabled = false
        isHardwareAvailable = false
        scanStatus = .idle
        isStarted = false
    }

    func requestScan() async {
        guard isStarted else { return }
        // FR39 / FR42: request Location authorization on first scan (the panel is the
        // introduction — no modal onboarding). The system no-ops repeat requests; guard so we
        // request exactly once and avoid log noise.
        if !didRequestAuthorization {
            didRequestAuthorization = true
            locationManager.requestWhenInUseAuthorization()
        }
        guard !isScanInFlight else { return }
        isScanInFlight = true
        scanStatus = .scanning
        let timeout = scanTimeoutNanoseconds
        #if DEBUG
        let override = _scanOverride
        #endif

        let task = Task { @MainActor [weak self] in
            defer {
                self?.isScanInFlight = false
                self?.inFlightScan = nil
            }
            do {
                let result = try await withThrowingTaskGroup(of: [WiFiNetwork].self) { group -> [WiFiNetwork] in
                    group.addTask(priority: .userInitiated) {
                        try Task.checkCancellation()
                        #if DEBUG
                        if let override { return try await override() }
                        #endif
                        // AC #3: heavy CoreWLAN scan runs on Task.detached. The TaskGroup awaits its value.
                        let detached = Task.detached(priority: .userInitiated) {
                            try Self.performScan()
                        }
                        return try await detached.value
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: timeout)
                        throw ScanTimeout()
                    }
                    let r = try await group.next()!
                    group.cancelAll()
                    return r
                }
                self?.networks = result.sorted { $0.rssi > $1.rssi }
                self?.scanStatus = .idle
            } catch is ScanTimeout {
                self?.scanStatus = .timedOut
            } catch is CancellationError {
                self?.scanStatus = .idle
            } catch {
                // Real scan errors (permission denied, hardware off, auth-algo unsupported)
                // are NOT timeouts. Reset networks and report idle so UI can re-issue without
                // showing a misleading "Scan timed out" copy.
                Log.networkWiFi.error("Scan failed: \(error.localizedDescription, privacy: .public)")
                self?.networks = []
                self?.scanStatus = .idle
            }
        }
        inFlightScan = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    nonisolated private static func performScan() throws -> [WiFiNetwork] {
        try Task.checkCancellation()
        guard let iface = CWWiFiClient.shared().interface() else { return [] }
        let connectedBSSID = iface.bssid()
        let scanned = try iface.scanForNetworks(withSSID: nil)
        try Task.checkCancellation()
        return scanned.map { cwNet -> WiFiNetwork in
            let bssid = cwNet.bssid
            let ssid = cwNet.ssid
            let security = WiFiSecurity(fromCWNetwork: cwNet)
            let id = bssid ?? "\(ssid ?? "hidden"):\(security)"
            return WiFiNetwork(
                id: id,
                ssid: ssid,
                bssid: bssid,
                rssi: cwNet.rssiValue,
                isConnected: bssid != nil && bssid == connectedBSSID,
                requiresPassword: security != .none && security != .enterprise,
                security: security,
                isCaptive: false
            )
        }
    }

    // MARK: - Association (Story 2.1)

    /// Associates with `network` (open variant when `password == nil`) and reports the outcome as
    /// a cause-typed `Result` (FR29, FR37). The blocking `CWInterface.associate(to:password:)`
    /// call runs on `Task.detached` (off the MainActor) exactly like `performScan`; only Sendable
    /// values (`ssid`, `bssid`, `password`) cross into the detached closure. The matching live
    /// `CWNetwork` is re-found inside that closure from a fresh `scanForNetworks` (preferred —
    /// the cache may be stale) keyed by BSSID when present, else by SSID; if no match is found we
    /// return `.failure(.outOfRange)`. Any thrown error is mapped to `WiFiConnectionFailure` via
    /// `failure(from:)` (symbolic `CWError.Code` first, pure numeric map as fallback) — no
    /// `NSError` leaves this method (UX-DR30). The monitor mutates no `@Published` state here, so it is left clean and
    /// retryable without restart (NFR10); `connectedNetwork` updates arrive via `CWEventDelegate`.
    func associate(network: WiFiNetwork, password: String?) async -> Result<Void, WiFiConnectionFailure> {
        #if DEBUG
        if let _associateOverride {
            return await _associateOverride(network, password)
        }
        #endif
        // Capture only Sendable values; never let CWNetwork/CWInterface cross the boundary.
        let ssid = network.ssid
        let bssid = network.bssid
        let detached = Task.detached(priority: .userInitiated) {
            Self.performAssociate(ssid: ssid, bssid: bssid, password: password)
        }
        return await detached.value
    }

    /// Pure-ish CoreWLAN association run off the MainActor. Re-finds the live `CWNetwork` by
    /// BSSID (or SSID for hidden networks) from a fresh scan, calls `associate(to:password:)`, and
    /// maps any thrown error to `WiFiConnectionFailure`. Returns a `Sendable` `Result`; no
    /// `CWNetwork`/`CWInterface` reference escapes this closure.
    nonisolated private static func performAssociate(
        ssid: String?,
        bssid: String?,
        password: String?
    ) -> Result<Void, WiFiConnectionFailure> {
        guard let iface = CWWiFiClient.shared().interface() else {
            return .failure(.outOfRange)
        }
        let scanned: [CWNetwork]
        do {
            scanned = Array(try iface.scanForNetworks(withSSID: ssid?.data(using: .utf8)))
        } catch {
            return .failure(Self.failure(from: error))
        }
        // Prefer BSSID (unique per AP); fall back to SSID match for hidden / pre-auth networks.
        let match = scanned.first { bssid != nil && $0.bssid == bssid }
            ?? scanned.first { ssid != nil && $0.ssid == ssid }
        guard let cwNet = match else {
            return .failure(.outOfRange)
        }
        do {
            try iface.associate(to: cwNet, password: password)
            return .success(())
        } catch {
            return .failure(Self.failure(from: error))
        }
    }

    /// Maps a thrown CoreWLAN error to a cause-typed `WiFiConnectionFailure`. Switches on the
    /// strongly-typed `CWError.Code` enum first — symbolic cases are stable across SDK versions,
    /// unlike the raw integer values. Only when the thrown error is not a `CWError` do we hand the
    /// raw `(error as NSError).code` to the pure `WiFiConnectionFailure.map(cwErrorCode:)` numeric
    /// fallback. This keeps `WiFiConnectionFailure` (Models, Foundation-only) CoreWLAN-free while
    /// giving the live path version-robust, name-based mapping.
    ///
    /// Wrong-password rationale: CoreWLAN surfaces a rejected PSK as `.notPermitted` (no dedicated
    /// numeric `CWErr` constant exists), so that case is recognized here, not in the numeric map.
    nonisolated private static func failure(from error: Error) -> WiFiConnectionFailure {
        guard let cwError = error as? CWError else {
            return WiFiConnectionFailure.map(cwErrorCode: (error as NSError).code)
        }
        switch cwError.code {
        case .notPermitted:
            // PSK rejected — the dominant, user-actionable cause is an incorrect passphrase.
            return .wrongPassword
        case .timeout, .deviceTimeout:
            // Association handshake stalled.
            return .associationTimeout
        case .unsupportedCapabilities, .unspecifiedFailure, .notSupported:
            // Radio could not reach / complete association with the target.
            return .outOfRange
        default:
            // Any other CWError — including the EAPOL/auth code (rawValue 1, no Swift enum case)
            // and anything new. Hand the raw integer to the pure numeric map, which recognizes
            // kCWEAPOLErr (1 → .authenticationError) and the timeout/out-of-range constants, and
            // preserves anything unrecognized as .unknown(code:).
            return WiFiConnectionFailure.map(cwErrorCode: (error as NSError).code)
        }
    }

    private func refreshFromCurrentInterface() {
        guard let iface = CWWiFiClient.shared().interface() else {
            if isHardwareAvailable { isHardwareAvailable = false }
            if isEnabled { isEnabled = false }
            if connectedNetwork != nil { connectedNetwork = nil }
            return
        }
        let nextEnabled = iface.powerOn()
        // Equality-guarded writes: avoid retriggering CombineLatest4 debounce on RSSI noise
        // when the underlying flags have not actually changed.
        if !isHardwareAvailable { isHardwareAvailable = true }
        if isEnabled != nextEnabled { isEnabled = nextEnabled }
        let next = Self.makeConnectedNetwork(from: iface, isEnabled: nextEnabled)
        if connectedNetwork != next { connectedNetwork = next }
    }

    private static func makeConnectedNetwork(from iface: CWInterface, isEnabled: Bool) -> WiFiNetwork? {
        guard isEnabled else { return nil }
        let bssid = iface.bssid()
        let ssid = iface.ssid()
        // Hidden / pre-auth networks may briefly withhold BSSID; an SSID alone is enough to
        // populate the connected entry and keep the icon stable through association.
        guard ssid != nil || bssid != nil else { return nil }
        let security = WiFiSecurity(fromCWInterface: iface)
        let id = bssid ?? "\(ssid ?? "hidden"):\(security)"
        return WiFiNetwork(
            id: id,
            ssid: ssid,
            bssid: bssid,
            rssi: iface.rssiValue(),
            isConnected: true,
            requiresPassword: security != .none && security != .enterprise,
            security: security,
            isCaptive: false
        )
    }

    // MARK: - CWEventDelegate (capture only Sendable `interfaceName: String`)

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in self?.eventSubject.send(()) }
    }
    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in self?.eventSubject.send(()) }
    }
    nonisolated func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) {
        Task { @MainActor [weak self] in self?.eventSubject.send(()) }
    }
    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in self?.eventSubject.send(()) }
    }

    // MARK: - CLLocationManagerDelegate

    /// Pure mapping of an authorization status to the denial flag. `static` + Sendable input so
    /// it is trivially unit-testable without a live `CLLocationManager`.
    static func isDenied(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .denied, .restricted:
            return true
        default:
            // .notDetermined / .authorized / .authorizedAlways / .authorizedWhenInUse → not denied.
            return false
        }
    }

    /// Swift 6 marks this delegate method `nonisolated`. The `CLAuthorizationStatus` is captured
    /// from the manager on MainActor (the manager is MainActor-owned), so we hop first, then read.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let denied = Self.isDenied(self.locationManager.authorizationStatus)
            let wasDenied = self.isLocationDenied
            if self.isLocationDenied != denied { self.isLocationDenied = denied }
            // FR41: denied → granted while running auto-retries the scan so the panel
            // transitions from the denial view to the list without an app restart.
            if wasDenied && !denied && self.isStarted {
                Task { @MainActor [weak self] in await self?.requestScan() }
            }
        }
    }
}

private struct ScanTimeout: Error {}

private extension WiFiSecurity {
    init(fromCWInterface iface: CWInterface) {
        self = WiFiSecurity.fromCWSecurity(iface.security())
    }

    init(fromCWNetwork cwNet: CWNetwork) {
        // Strongest-first ordering: WPA3-Transition advertises `.none` for backwards-compat;
        // checking `.none` first would mis-classify it as open.
        if cwNet.supportsSecurity(.wpa3Personal) || cwNet.supportsSecurity(.wpa3Transition) {
            self = .wpa3Personal
        } else if cwNet.supportsSecurity(.wpa2Personal)
                    || cwNet.supportsSecurity(.wpaPersonal)
                    || cwNet.supportsSecurity(.wpaPersonalMixed) {
            self = .wpa2Personal
        } else if cwNet.supportsSecurity(.wpa2Enterprise)
                    || cwNet.supportsSecurity(.wpaEnterprise)
                    || cwNet.supportsSecurity(.wpaEnterpriseMixed)
                    || cwNet.supportsSecurity(.wpa3Enterprise)
                    || cwNet.supportsSecurity(.enterprise) {
            self = .enterprise
        } else if cwNet.supportsSecurity(.none) {
            self = .none
        } else {
            self = .other
        }
    }

    static func fromCWSecurity(_ cwSecurity: CWSecurity) -> WiFiSecurity {
        switch cwSecurity {
        case .none:
            return .none
        case .wpa2Personal, .wpaPersonal, .wpaPersonalMixed:
            return .wpa2Personal
        case .wpa3Personal, .wpa3Transition:
            return .wpa3Personal
        case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .wpa3Enterprise, .enterprise:
            return .enterprise
        default:
            return .other
        }
    }
}
