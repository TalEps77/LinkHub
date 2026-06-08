# Story 2.1: WiFiMonitor.associate + Cause-Typed Connection Failure

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user,
I want LinkHub to attempt Wi-Fi connections via CoreWLAN and surface specific failure causes,
so that when a connection fails I can tell whether the password is wrong, the network is out of range, or something else is wrong.

## Acceptance Criteria

1. **Open-network association reports via a typed result (FR29)**
   - **Given** the user requests a connection to an open network
   - **When** `WiFiMonitor.associate(network:password:)` is called with `password == nil`
   - **Then** the call invokes `CWInterface.associate(to:password:)` (open variant — `password` forwarded as `nil`) and reports success or failure via a typed `Result<Void, WiFiConnectionFailure>`

2. **Cause-typed failure enum + `CWErrorDomain` mapping (FR37)**
   - **Given** a connection attempt fails
   - **When** the `CWErrorDomain` code is mapped
   - **Then** `Network/Models/WiFiConnectionFailure.swift` defines `enum WiFiConnectionFailure: Error, Equatable, Sendable { case wrongPassword; case outOfRange; case associationTimeout; case authenticationError; case unknown(code: Int) }`
   - **And** mapping covers the relevant `CWErrorDomain` codes via a pure, static, unit-testable mapper

3. **Clean, retryable state on completion (NFR10)**
   - **Given** a connection attempt completes (success or failure)
   - **When** the result lands on MainActor
   - **Then** the app remains in a clean state — the user can retry without restart
   - **And** any error is surfaced via the typed `Result`, never via `NSAlert` (UX-DR30) — inline UI rendering is Story 2.3

4. **Layer-typed errors only — no `NSError` leak (UX-DR30)**
   - **Given** a connection attempt
   - **When** errors propagate
   - **Then** layer-typed `WiFiConnectionFailure` values are used; no `NSError`/`CWError` rethrow leaks past the Network layer

## Tasks / Subtasks

- [x] **Task 1: `Network/Models/WiFiConnectionFailure.swift` — cause-typed error + pure numeric mapper** (AC: #2, #4)
  - [x] `enum WiFiConnectionFailure: Error, Equatable, Sendable` with the five cases exactly as specified
  - [x] `static func map(cwErrorCode: Int) -> WiFiConnectionFailure` — pure, Foundation-only, no CoreWLAN import. Maps the canonical `CWErr` integer constants; unrecognized → `.unknown(code:)`
  - [x] `import Foundation` only — Models-layer purity preserved (architecture.md "Network/Models/ … no CoreWLAN")
- [x] **Task 2: `WiFiMonitorProtocol` — add `associate(network:password:)`** (AC: #1)
  - [x] `func associate(network: WiFiNetwork, password: String?) async -> Result<Void, WiFiConnectionFailure>`
  - [x] Update the top-of-file scope comment (Story 2.1 adds associate; Keychain/disconnect/power still out of scope)
- [x] **Task 3: `WiFiMonitor.associate` + off-MainActor association** (AC: #1, #3, #4)
  - [x] `associate(network:password:)` captures only Sendable values (`ssid`, `bssid`, `password`), dispatches the blocking CoreWLAN work to `Task.detached(priority: .userInitiated)`, awaits its `.value` (returns to MainActor)
  - [x] `nonisolated static func performAssociate(ssid:bssid:password:)` — re-finds the live `CWNetwork` from a fresh `scanForNetworks` (BSSID-keyed, SSID fallback), calls `associate(to:password:)`; no `CWNetwork`/`CWInterface` escapes the closure; no matching network → `.failure(.outOfRange)`
  - [x] `nonisolated static func failure(from:)` — maps a thrown CoreWLAN error to `WiFiConnectionFailure` via the strongly-typed `CWError.Code` switch first, numeric `map(cwErrorCode:)` fallback otherwise
  - [x] `#if DEBUG _associateOverride` test seam (mirrors `_scanOverride`)
- [x] **Task 4: Conformer / stub updates** (AC: #1)
  - [x] `MockWiFiMonitor.associate` — `var nextAssociateResult` settable result; 200 ms simulated delay (mirrors `requestScan`); honors cancellation
  - [x] `StubWiFiMonitor` (AppStateTests) — trivial `.success(())`
  - [x] `PopoverStubWiFiMonitor` (PopoverControllerTests) — trivial `.success(())`
- [x] **Task 5: Tests** (AC: all)
  - [x] `WiFiConnectionFailureTests` — table-driven numeric mapper, all known codes + `.unknown` fallthrough + distinct-code preservation
  - [x] `WiFiMonitorTests` — `associate` happy/failure paths via `_associateOverride`; open-network nil-password forwarding; each cause-typed failure; retryable-after-failure (NFR10)

## Dev Notes

### Story foundation

Story 2.1 delivers the **write-path contract** for Wi-Fi: `WiFiMonitor.associate(network:password:)` returns a cause-typed `Result<Void, WiFiConnectionFailure>` (FR29/FR37). It does NOT build any UI (Story 2.3 renders the inline error caption), does NOT touch Keychain (Story 2.2), and does NOT add disconnect / power-toggle / captive handling (Story 2.5). The method is surgical: it mutates no `@Published` state, so the monitor is left clean and retryable without restart (NFR10); `connectedNetwork` updates continue to arrive via the existing `CWEventDelegate` path from Story 1.3.

### CWErrorDomain → WiFiConnectionFailure mapping (the key decision)

CoreWLAN association errors arrive as `CWError` (domain `CWErrorDomain`). There are **two** representations: the modern strongly-typed `CWError.Code` enum (symbolic, version-stable) and the underlying integer `CWErr` constants from `<CoreWLAN/CWError.h>`. The mapping is split deliberately across two tiers:

**Tier 1 — live boundary (`WiFiMonitor.failure(from:)`, imports CoreWLAN):** switches on `CWError.Code` symbolic cases. Symbolic names are robust across SDK versions, unlike raw integers. Recognized: `.notPermitted → .wrongPassword`, `.timeout`/`.deviceTimeout → .associationTimeout`, `.unsupportedCapabilities`/`.unspecifiedFailure`/`.notSupported → .outOfRange`. Anything else falls through to Tier 2.

**Tier 2 — pure numeric mapper (`WiFiConnectionFailure.map(cwErrorCode:)`, Foundation-only):** the unit-testable contract. The Models layer never imports CoreWLAN, so the mapper takes a plain `Int`. It backs up Tier 1 (catching e.g. the EAPOL code that has no Swift enum case, and non-`CWError` `NSError`s) and is what the tests exercise.

| `CWErrorDomain` code | `CWErr` constant | `CWError.Code` (Tier 1) | → case |
|---|---|---|---|
| -3905 | `kCWTimeoutErr` | `.timeout` | `.associationTimeout` |
| -3908 | `kCWDeviceTimeoutErr` | `.deviceTimeout` | `.associationTimeout` |
| 1 | `kCWEAPOLErr` | *(no Swift case → numeric fallback)* | `.authenticationError` |
| -3907 | `kCWUnsupportedCapabilitiesErr` | `.unsupportedCapabilities` | `.outOfRange` |
| -3906 | `kCWUnspecifiedFailureErr` | `.unspecifiedFailure` | `.outOfRange` |
| -3903 | `kCWNotSupportedErr` | `.notSupported` | `.outOfRange` |
| *(PSK rejected)* | *(no dedicated `CWErr` constant)* | `.notPermitted` | `.wrongPassword` |
| (any other) | — | `default` → numeric fallback | `.unknown(code:)` |

**Wrong-password rationale:** CoreWLAN does NOT expose a dedicated numeric constant for "PSK rejected." An incorrect passphrase surfaces as the modern `CWError.Code.notPermitted` (whose raw value is not pinned across SDKs) or, on some paths, as a timeout. `.wrongPassword` is therefore driven by the **symbolic** Tier-1 switch, NOT a hard-coded integer. This is why the numeric mapper has no `wrongPassword` row — that was an earlier draft (`-3911`) that did not correspond to any documented `kCW…` constant and was removed.

### CWNetwork-lookup decision

`CWInterface.associate(to:password:)` takes a live `CWNetwork`, which is **not** `Sendable` and must never cross the actor boundary (architecture.md "CWNetwork must never cross actor boundaries"). The chosen approach: `performAssociate` runs entirely inside `Task.detached`, captures only the Sendable `ssid`/`bssid`/`password` strings, and **re-finds** the `CWNetwork` there via a fresh `iface.scanForNetworks(withSSID:)`:

- Match preference: **BSSID** (unique per AP) first, then **SSID** (for hidden / pre-auth networks whose BSSID we may not have).
- A fresh scan (vs. `cachedScanResults()`) is preferred because the cache may be stale between panel display and the connect tap; an associate against a vanished AP is the exact "out of range" condition we want to surface.
- No matching `CWNetwork` found → `.failure(.outOfRange)` (per design constraint).
- No `CWNetwork`/`CWInterface` reference escapes the detached closure — only the Sendable `Result` value returns.

This diverges from docs/06's `connect(to:)` pseudocode, which re-fetches from `cachedScanResults()` keyed by BSSID only. The fresh-scan + SSID-fallback approach is strictly more robust for hidden networks and stale caches; the BSSID-only cache lookup would mis-classify a moved-channel or hidden AP as not-found.

### Spec divergences (documented)

1. **`Result` return vs. `throws`.** architecture.md's "Good — typed layer error" sketch and docs/06's `connect(to:) async throws` both show a *throwing* API. Story 2.1's ACs + design constraints mandate a non-throwing `async -> Result<Void, WiFiConnectionFailure>`. The `Result` form is used (authoritative per the story brief); it makes the success/failure contract explicit at the type level and keeps `CWError` from ever being rethrown.
2. **Method name `associate` vs. `connect`.** docs/06 / architecture.md name the write method `connect(to:password:remember:)`. Story 2.1 uses `associate(network:password:)` per the epic AC wording and the brief. The `remember` flag and Keychain write are Story 2.2; they are intentionally absent here.
3. **Numeric `-3911 → wrongPassword` removed.** A prior draft mapped `-3911` ("kCWNotPermittedErr") to `.wrongPassword`. That integer is not a documented `CWErr` constant; wrong-password is now recognized symbolically via `CWError.Code.notPermitted` (Tier 1). The numeric mapper no longer claims it.
4. **Fresh scan vs. `cachedScanResults()`** for the `CWNetwork` lookup — see above.

### Concurrency & isolation (must-follow)

- `WiFiMonitor` is `@MainActor final class`. `associate` is `@MainActor`; the blocking `scanForNetworks` + `associate(to:password:)` run on `Task.detached(priority: .userInitiated)`, exactly mirroring `requestScan` → `performScan`.
- `performAssociate` and `failure(from:)` are `nonisolated static` — no `self`, no actor state, Sendable-clean. Only `String?`/`Result` cross the boundary.
- `Result<Void, WiFiConnectionFailure>` is `Sendable` (`Void` and the enum are both Sendable), so awaiting `detached.value` back on MainActor is clean.
- `_associateOverride` is `#if DEBUG` and typed `(@Sendable (WiFiNetwork, String?) async -> Result<Void, WiFiConnectionFailure>)?`, matching the `_scanOverride` seam.
- No `NSAlert`, no `DispatchQueue.main.async`, no `try?`-swallowing — every thrown error is mapped explicitly through `failure(from:)`.

### Anti-patterns avoided

- **No** `CWNetwork`/`CWInterface` captured across the actor boundary — re-found inside the detached closure from Sendable strings.
- **No** `NSError`/`CWError` rethrown past the Network layer — all errors become `WiFiConnectionFailure`.
- **No** `@Published` mutation in `associate` — keeps the monitor clean & retryable (NFR10); association state flows through the existing `CWEventDelegate` debounce path.
- **No** Keychain / disconnect / power-toggle / captive code (Stories 2.2 / 2.5).
- **No** UI — inline error rendering is Story 2.3.
- **No** magic-number reliance for `.wrongPassword` — symbolic `CWError.Code` at the live boundary.

### File-structure requirements

| File | Status | Purpose |
|---|---|---|
| `LinkHub/Network/Models/WiFiConnectionFailure.swift` | NEW | `enum WiFiConnectionFailure` + pure `map(cwErrorCode:)` |
| `LinkHub/Network/WiFiMonitor.swift` | MODIFIED | `associate`, `performAssociate`, `failure(from:)`, `_associateOverride` seam |
| `LinkHub/Network/WiFiMonitorProtocol.swift` | MODIFIED | Add `associate(network:password:)` requirement |
| `LinkHub/Network/MockWiFiMonitor.swift` | MODIFIED | `associate` + `nextAssociateResult` |
| `LinkHubTests/Network/Models/WiFiConnectionFailureTests.swift` | NEW | Table-driven mapper coverage |
| `LinkHubTests/Network/WiFiMonitorTests.swift` | MODIFIED | `associate` happy/failure/open/retryable tests |
| `LinkHubTests/State/AppStateTests.swift` | MODIFIED | `StubWiFiMonitor.associate` conformance |
| `LinkHubTests/MenuBar/PopoverControllerTests.swift` | MODIFIED | `PopoverStubWiFiMonitor.associate` conformance |

### Test seam & coverage notes

- `WiFiConnectionFailureTests` runs on any host (no CoreWLAN, no hardware) — the mapper is a pure `Int → enum` function.
- `WiFiMonitorTests` associate tests use `_associateOverride` so they never touch live CoreWLAN; they assert the `Result` contract, the open-network `nil`-password forwarding, every cause-typed failure, and retryability after failure (NFR10).
- `failure(from:)` is `private` and CoreWLAN-dependent, so it is verified by code review + the numeric mapper tests rather than a direct unit test (constructing a real `CWError` with a specific code without hardware is unreliable across SDKs).

## Dev Agent Record

### Completion Notes

- `WiFiConnectionFailure` (5 cases, `Error, Equatable, Sendable`) + pure `map(cwErrorCode:)` live in Models, `import Foundation` only.
- `WiFiMonitor.associate` dispatches the blocking CoreWLAN association to `Task.detached`, capturing only Sendable `ssid`/`bssid`/`password`; `performAssociate` re-finds the `CWNetwork` (BSSID-first, SSID fallback) and never lets a non-Sendable reference escape; missing network → `.failure(.outOfRange)`.
- Error mapping is two-tier: symbolic `CWError.Code` switch at the live boundary (`failure(from:)`), pure numeric `map(cwErrorCode:)` fallback + unit-test contract. `.wrongPassword` is symbolic-only (no `CWErr` numeric constant exists); `.authenticationError` (EAPOL = 1) is caught by the numeric fallback.
- Every `WiFiMonitorProtocol` conformer updated: `MockWiFiMonitor` (settable `nextAssociateResult`, 200 ms delay, cancellation→`.associationTimeout`), `StubWiFiMonitor`, `PopoverStubWiFiMonitor`.
- `#if DEBUG _associateOverride` seam added (mirrors `_scanOverride`) so associate is exercisable without hardware.
- No `@Published` mutation in associate → monitor stays clean / retryable (NFR10). No `NSError`/`NSAlert` past the Network layer (UX-DR30). No Keychain / disconnect / power / captive / UI (out of scope).

### File List

**New (LinkHub/):**
- LinkHub/Network/Models/WiFiConnectionFailure.swift

**Modified (LinkHub/):**
- LinkHub/Network/WiFiMonitor.swift
- LinkHub/Network/WiFiMonitorProtocol.swift
- LinkHub/Network/MockWiFiMonitor.swift

**New (LinkHubTests/):**
- LinkHubTests/Network/Models/WiFiConnectionFailureTests.swift

**Modified (LinkHubTests/):**
- LinkHubTests/Network/WiFiMonitorTests.swift
- LinkHubTests/State/AppStateTests.swift
- LinkHubTests/MenuBar/PopoverControllerTests.swift

**Generated (re-generated by xcodegen, not hand-edited):**
- LinkHub.xcodeproj/

### Change Log

| Date | Change |
|---|---|
| 2026-06-08 | Story created and implemented via bmad dev-story. `WiFiConnectionFailure` + two-tier `CWErrorDomain` mapping (symbolic `CWError.Code` at boundary, pure numeric mapper for tests), `WiFiMonitor.associate` off-MainActor with Sendable-only captures + fresh-scan CWNetwork lookup, `_associateOverride` seam, all conformers updated, mapper + associate tests added. Status: review. |
| 2026-06-08 | code-review (orchestrator, static): verified off-MainActor detached association with Sendable-only captures (no CWNetwork/CWInterface escape), Result<Void, WiFiConnectionFailure> Sendable across the boundary, all 5 conformers updated, no @Published mutation in associate (NFR10 clean/retryable). PRIMARY LOCAL-BUILD RISK: the `CWError.Code` symbolic case spellings in `failure(from:)` (`.notPermitted` load-bearing for `.wrongPassword`); numeric fallback backs up the rest. Status → done. |
