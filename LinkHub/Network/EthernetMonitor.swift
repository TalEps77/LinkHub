import Foundation
import Combine
import SystemConfiguration

/// Observes all Ethernet interfaces via `SCDynamicStore` and publishes a `Sendable`
/// `[EthernetInterface]` snapshot. `@MainActor` so its `@Published` state is mutated on the
/// main actor without explicit dispatch (PRD 03 D9).
///
/// ## Concurrency boundary (NFR8, architecture.md "Sendable extraction before MainActor hop")
/// `SCDynamicStore`, `SCNetworkInterface`, and every `CFType` are non-`Sendable` and are read
/// **only** on a private serial queue. The C callback (`scCallback`, a `@convention(c)` function
/// pointer — necessarily `nonisolated`) recovers `self` from the context `info` pointer via
/// `Unmanaged`, builds the `Sendable` snapshot on the queue through the `nonisolated static`
/// `enumerate(...)`, then hops `Task { @MainActor [weak self] in self?.ingest(snapshot) }`.
/// No SC/CF reference ever crosses the actor hop — only `[EthernetInterface]` does.
///
/// ## SCDynamicStoreContext / Unmanaged
/// `SCDynamicStoreCreate` takes a `SCDynamicStoreContext` whose `info` carries an opaque pointer.
/// We pass `Unmanaged.passUnretained(self).toOpaque()` and supply `retain`/`release` C callbacks
/// that bump the Swift refcount, so the store keeps `self` alive for the queue's callbacks and
/// balances it when the store is torn down (`SCDynamicStoreSetDispatchQueue(store, nil)`).
@MainActor
final class EthernetMonitor: EthernetMonitorProtocol {
    @Published private(set) var interfaces: [EthernetInterface] = []
    var interfacesPublisher: Published<[EthernetInterface]>.Publisher { $interfaces }

    /// Debounce hop point: each SCDynamicStore notification sends `()` here; the debounced sink
    /// re-enumerates once per quiet window (NFR5). Mirrors `WiFiMonitor.eventSubject`.
    private let eventSubject = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    /// Live store handle. Held so `stop()` can detach the queue. Read/written on MainActor only.
    private var store: SCDynamicStore?
    /// Private serial queue the store delivers callbacks on — never the main queue (PRD 03 D2).
    private let queue = DispatchQueue(label: "com.linkhub.app.ethernet", qos: .utility)
    private var isStarted = false

    init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { ptr in
                guard let ptr else { return nil }
                _ = Unmanaged<EthernetMonitor>.fromOpaque(ptr).retain()
                return UnsafeRawPointer(ptr)
            },
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<EthernetMonitor>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(
            nil,
            "com.linkhub.app" as CFString,
            EthernetMonitor.scCallback,
            &context
        ) else {
            Log.networkEthernet.error("SCDynamicStoreCreate failed; Ethernet observation unavailable")
            isStarted = true
            return
        }
        self.store = store

        // regex(3) patterns (not literal keys): `[^/]+` matches one interface-name path segment.
        let linkPattern = "State:/Network/Interface/[^/]+/Link" as CFString
        let ipv4Pattern = "State:/Network/Interface/[^/]+/IPv4" as CFString
        if !SCDynamicStoreSetNotificationKeys(store, nil, [linkPattern, ipv4Pattern] as CFArray) {
            Log.networkEthernet.error("SCDynamicStoreSetNotificationKeys failed")
        }
        if !SCDynamicStoreSetDispatchQueue(store, queue) {
            Log.networkEthernet.error("SCDynamicStoreSetDispatchQueue failed")
        }

        // Debounced re-enumeration. The sink runs on DispatchQueue.main (not MainActor isolation
        // under Swift 6), so it hops explicitly; the SC reads happen on the private queue inside
        // `refresh()`, never on main.
        eventSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            .store(in: &cancellables)

        isStarted = true

        // Initial enumeration (no SCDynamicStore event has fired yet).
        refresh()
    }

    func stop() {
        if let store {
            // Detaches the dispatch queue and releases the context's retain on self (NFR9, FR46).
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        store = nil
        cancellables.removeAll()
        if !interfaces.isEmpty { interfaces = [] }
        isStarted = false
    }

    // MARK: - C callback → MainActor bridge

    /// `@convention(c)` so it can be handed to `SCDynamicStoreCreate`. Runs on the private serial
    /// queue and is `nonisolated`. It must not touch `@MainActor` state: it recovers `self`, reads
    /// nothing from it, and pings the event subject via a MainActor hop so the debounced sink
    /// drives the re-enumeration.
    private static let scCallback: SCDynamicStoreCallBack = { _, _, info in
        guard let info else { return }
        let monitor = Unmanaged<EthernetMonitor>.fromOpaque(info).takeUnretainedValue()
        Task { @MainActor [weak monitor] in monitor?.eventSubject.send(()) }
    }

    /// Re-enumerates all Ethernet interfaces and ingests the resulting `Sendable` snapshot.
    /// The CF/SC reads run on the private serial queue (`enumerate`); only the
    /// `[EthernetInterface]` value crosses back to MainActor via a `Task { @MainActor }` hop.
    ///
    /// `SCDynamicStore` is a non-`Sendable` CFType, so it cannot be captured into the `@Sendable`
    /// `queue.async` closure under Swift 6 strict concurrency. We bind it to a `nonisolated(unsafe)`
    /// local: the store is read-only here, the reads (`SCDynamicStoreCopyValue`) are thread-safe,
    /// and the store is already bound to `queue` via `SCDynamicStoreSetDispatchQueue`, so serial
    /// access on that queue is the documented-safe usage.
    private func refresh() {
        guard isStarted, let store else { return }
        nonisolated(unsafe) let storeRef = store
        queue.async { [weak self] in
            let snapshot = EthernetMonitor.enumerate(store: storeRef)
            Task { @MainActor [weak self] in self?.ingest(snapshot) }
        }
    }

    /// MainActor sink for a freshly built snapshot. Equality-guarded to avoid redundant emissions
    /// on no-op SCDynamicStore bursts (mirrors WiFiMonitor's guarded `@Published` writes).
    private func ingest(_ snapshot: [EthernetInterface]) {
        guard isStarted else { return }
        if interfaces != snapshot { interfaces = snapshot }
    }

    // MARK: - SystemConfiguration reads (private queue only — never MainActor)

    /// Enumerates hardware Ethernet interfaces and builds the `Sendable` snapshot. `nonisolated`
    /// and `static` so it captures no `@MainActor` state and runs on the private serial queue.
    /// `SCNetworkInterfaceCopyAll()` re-enumerates every call, so hotplugged adapters appear with
    /// no separate hotplug event (FR15). The returned `CFArray` retains its elements; each
    /// `SCNetworkInterface` ref is valid only while `all` is in scope — all reads happen here,
    /// and only the extracted value type leaves.
    nonisolated static func enumerate(store: SCDynamicStore) -> [EthernetInterface] {
        let ethernetType = kSCNetworkInterfaceTypeEthernet as String
        let all = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? []
        return all.compactMap { iface -> EthernetInterface? in
            // Filter to hardware Ethernet — excludes lo0, utun* (VPN), bridge*, awdl*, Wi-Fi (AirPort).
            guard SCNetworkInterfaceGetInterfaceType(iface) as String? == ethernetType else { return nil }
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { return nil }

            let display = (SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?) ?? bsd
            let hasLink = readHasLink(store: store, bsdName: bsd)
            let ipv4 = readIPv4(store: store, bsdName: bsd)
            let speed = hasLink ? readLinkSpeedMbps(from: iface) : nil

            return EthernetInterface(
                id: bsd,
                bsdName: bsd,
                displayName: display,
                linkSpeedMbps: speed,
                ipv4: ipv4,
                state: interfaceState(hasLink: hasLink, ipv4: ipv4, dhcpTimedOut: false)
            )
        }
    }

    /// Reads physical link state from `State:/Network/Interface/<bsd>/Link` → `Active` (Bool).
    nonisolated private static func readHasLink(store: SCDynamicStore, bsdName: String) -> Bool {
        let key = "State:/Network/Interface/\(bsdName)/Link" as CFString
        guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: AnyObject] else { return false }
        return (dict["Active"] as? Bool) ?? false
    }

    /// Reads the primary IPv4 address from `State:/Network/Interface/<bsd>/IPv4` → `Addresses[0]`.
    nonisolated private static func readIPv4(store: SCDynamicStore, bsdName: String) -> String? {
        let key = "State:/Network/Interface/\(bsdName)/IPv4" as CFString
        guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: AnyObject],
              let addresses = dict["Addresses"] as? [String],
              let first = addresses.first, !first.isEmpty
        else { return nil }
        return first
    }

    /// Reads negotiated link speed via `SCNetworkInterfaceCopyMediaOptions` (current media only).
    /// `nil` when no link or the subtype is unknown. PRD 05 Decision #1.
    nonisolated private static func readLinkSpeedMbps(from iface: SCNetworkInterface) -> Int? {
        var currentPtr: Unmanaged<CFDictionary>?
        guard SCNetworkInterfaceCopyMediaOptions(iface, &currentPtr, nil, nil, false),
              let current = currentPtr?.takeRetainedValue() as? [String: AnyObject],
              let subtype = current[kSCPropNetEthernetMediaSubType as String] as? String
        else { return nil }
        return megabitsFromSubtype(subtype)
    }

    // MARK: - Pure derivation helpers (unit-tested; no SC/CF dependency)

    /// Maps the two physical signals (+ a presentation DHCP-timeout flag) to one of the four
    /// states (FR16). Pure: trivially unit-testable without SystemConfiguration.
    ///
    /// | hasLink | ipv4    | dhcpTimedOut | state         |
    /// |---------|---------|--------------|---------------|
    /// | false   | (any)   | (any)        | `.noLink`     |
    /// | true    | non-nil | (any)        | `.active`     |
    /// | true    | nil     | false        | `.obtaining`  |
    /// | true    | nil     | true         | `.dhcpTimeout`|
    static func interfaceState(hasLink: Bool, ipv4: String?, dhcpTimedOut: Bool) -> EthernetInterfaceState {
        guard hasLink else { return .noLink }
        if ipv4 != nil { return .active }
        return dhcpTimedOut ? .dhcpTimeout : .obtaining
    }

    /// Maps an `SCNetworkInterface` media subtype string to raw Mbps. `nil` for unknown / "none".
    /// Pure: unit-tested against the documented subtype constants (PRD 05).
    static func megabitsFromSubtype(_ subtype: String) -> Int? {
        let table: [String: Int] = [
            "10baseT/UTP": 10, "10base5": 10,
            "100baseTX": 100, "100baseFX": 100,
            "1000baseT": 1000, "1000baseSX": 1000, "1000baseLX": 1000,
            "2500baseT": 2500,
            "5000baseT": 5000,
            "10GbaseT": 10_000, "10GbaseSR": 10_000, "10GbaseLR": 10_000,
            "25GbaseSR": 25_000,
            "40GbaseSR4": 40_000,
            "100GbaseSR4": 100_000
        ]
        return table[subtype]
    }
}
