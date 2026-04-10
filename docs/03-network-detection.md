# PRD 03 — Network Detection & Observation

**Status:** ⬜ Not Started  
**Depends on:** 01  
**Blocks:** 05, 06, 07, 08

---

## Problem Statement

> Which frameworks and APIs will detect and observe Ethernet and Wi-Fi state changes, and
> how will those events be surfaced to the rest of the app?

This PRD must decide:

- **Ethernet detection framework** — `SystemConfiguration` (`SCDynamicStore` /
  `SCNetworkReachability`) vs. `Network.framework` (`NWPathMonitor`) vs.
  `IOKit`; which provides reliable link-state (up/down) detection for wired
  interfaces including USB-C Ethernet dongles
- **Wi-Fi detection framework** — `CoreWLAN` (`CWWiFiClient`) vs.
  `Network.framework` (`NWPathMonitor`) vs. a combination; which provides SSID,
  RSSI, security type, and association state without requiring undocumented APIs
- **Interface enumeration strategy** — how to discover all active Ethernet
  interfaces at launch and when new ones appear (e.g., dongles hotplugged);
  whether to enumerate once or maintain a live list
- **Push vs. polling** — whether each monitor registers for OS-pushed
  notifications (SCDynamicStore keys, CWEventDelegate) or polls on a timer;
  hybrid strategies; battery/CPU cost trade-offs for a persistent menu bar app
- **Event debounce** — minimum quiet period before publishing a state change
  upstream; where debounce lives (inside the monitor or in AppState); which
  debounce primitive to use (Combine `.debounce`, `Task.sleep`, serial queue)
- **Data model** — the exact types (`EthernetInterface`, `WiFiNetwork`,
  `NetworkState`, `ConnectionMode`) that monitors produce and `AppState`
  consumes; value-type shapes, field names, and `Sendable` conformances; where
  these types live in the PRD 01 folder layout
- **Threading and actor isolation** — which queue/actor each monitor's callback
  runs on; how results are safely handed off to `@MainActor AppState` under
  Swift 6 strict concurrency
- **Edge cases** — multiple simultaneous Ethernet adapters; USB-C dongles
  appearing/disappearing; VPN tunnel interfaces that masquerade as Ethernet;
  Wi-Fi disabled in System Settings; airplane-mode-like scenarios; interfaces
  that are "up" but have no IP address

## Decision Log

| Decision | Options Considered | Choice | Rationale |
|----------|--------------------|--------|-----------|

## Constraints

## Out of Scope

## Open Questions

## References
