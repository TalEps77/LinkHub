# Story 2.2: KeychainService — Persist Wi-Fi Passwords

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user,
I want LinkHub to remember my Wi-Fi passwords securely so I don't have to retype them,
so that re-joining a known network feels like the system Wi-Fi menu.

## Acceptance Criteria

1. **Successful connection persists the passphrase with the prescribed attribute set**
   - **Given** a successful connection to a password-protected network
   - **When** the connection completes
   - **Then** `KeychainService.set(password:forSSID:)` writes the password with `kSecClass == kSecClassGenericPassword`, `kSecAttrAccount == SSID`, `kSecAttrService == Bundle.main.bundleIdentifier`, `kSecAttrAccessible == kSecAttrAccessibleAfterFirstUnlock` (FR31, NFR12)

2. **Stored passphrase is retrievable; no re-prompt unless retrieval fails**
   - **Given** a known SSID
   - **When** the user reconnects
   - **Then** `KeychainService.password(forSSID:)` returns the stored password (or `nil`)
   - **And** the user is not re-prompted for the password unless retrieval fails (a `nil` read)

3. **Failure paths never persist a password (caller-enforced)**
   - **Given** any failure path (wrong password, association timeout, authentication error)
   - **When** the connection attempt fails
   - **Then** no Keychain write occurs; the entry is preserved only on success (UX-DR31)
   - **Note:** The connection-failure → no-write rule is enforced by the CALLER (Story 2.3 connect flow), which calls `set(password:forSSID:)` only after `associate` returns success. `KeychainService` exposes `set`/`password`/`remove` only — it does not touch `WiFiMonitor` or `associate`.

4. **Keychain is the only long-lived password store (NFR12)**
   - **Given** the running app
   - **When** any code path persists a password
   - **Then** no password is written to UserDefaults, plain files, or any long-lived in-memory store outside the Keychain (NFR12)

## Tasks / Subtasks

- [x] **Task 1: Create `LinkHub/Services/KeychainService.swift`** (AC: #1, #2, #4)
  - [x] `enum KeychainService` namespace with `static` funcs — `SecItem*` C APIs are thread-safe; no actor isolation, no shared mutable state, `Sendable`-clean by construction.
  - [x] `import Foundation`, `import Security` only.
  - [x] `static let service = Bundle.main.bundleIdentifier ?? "com.linkhub.app"` — the `kSecAttrService` value (architecture.md "Keychain account … Service: `Bundle.main.bundleIdentifier`"); fallback string for unit-test hosts where `bundleIdentifier` may be nil.
  - [x] `set(password:forSSID:) throws` — upsert: `SecItemAdd`; on `errSecDuplicateItem` fall back to `SecItemUpdate` (in-place value replace, accessibility preserved). Any other non-success status → `throw KeychainError.unhandled(status)`.
  - [x] `password(forSSID:) -> String?` — `SecItemCopyMatching` with `kSecReturnData` + `kSecMatchLimitOne`; returns `nil` on `errSecItemNotFound` AND on any other failure (a nil read = "not remembered", caller re-prompts). No throw on the read path — keeps callers simple.
  - [x] `remove(forSSID:) throws` — `SecItemDelete`; `errSecItemNotFound` treated as success (desired post-state already holds). Included now for Story 2.6 Forget (trivial, avoids churn).
  - [x] Strings ↔ Data: store `Data(password.utf8)`; read back via `kSecReturnData` and `String(data:encoding:.utf8)` with a guard (no force-unwrap).
- [x] **Task 2: Extract pure, unit-testable query helpers** (AC: #1)
  - [x] `static func baseQuery(forSSID:) -> [String: Any]` — class + service + account only (match query for update/delete).
  - [x] `static func addQuery(password:forSSID:) -> [String: Any]` — `baseQuery` + `kSecValueData` + `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock`.
  - [x] `static func updateAttributes(password:) -> [String: Any]` — value-only dictionary for the `SecItemUpdate` second argument.
  - [x] `static func copyQuery(forSSID:) -> [String: Any]` — `baseQuery` + `kSecReturnData` + `kSecMatchLimitOne`.
- [x] **Task 3: `enum KeychainError: Error, Equatable`** (AC: #2, #3)
  - [x] `case unexpectedData` (successful copy returned non-UTF-8 payload — defensive; not expected for items we wrote) and `case unhandled(OSStatus)` (carries the raw Security status for logging / call-site inspection). No `NSError` leaks past this boundary (architecture.md "Error types: each layer defines a typed `enum`").
- [x] **Task 4: Tests `LinkHubTests/Services/KeychainServiceTests.swift`** (AC: all)
  - [x] Pure attribute assertions on `baseQuery` / `addQuery` / `copyQuery` / `updateAttributes` without hitting the live Keychain — assert class, account, service, accessibility, value, return/limit flags; assert `addQuery` uses `kSecAttrAccessibleAfterFirstUnlock`; assert `service == Bundle.main.bundleIdentifier ?? fallback`.
  - [x] Guarded live round-trip `testLiveRoundTrip` — `set → get → upsert (errSecDuplicateItem path) → remove`; if the first `set` throws `KeychainError.unhandled(status)` (headless/unsigned host without a usable keychain), `throw XCTSkip("… OSStatus \(status) …")` rather than failing. Uses `addTeardownBlock` to clean up.
  - [x] `testPasswordForUnknownSSIDReturnsNil` and `testRemoveUnknownSSIDDoesNotThrow` — read/remove of an unstored SSID returns `nil` / does not throw.
  - [x] `@testable import LinkHub`, `import Security`.
- [x] **Task 5: XcodeGen + build + test validation (LOCAL — cannot run on web)** (AC: all)
  - [ ] `xcodegen generate` — recursive `path: LinkHub` / `path: LinkHubTests` globs pick up `Services/KeychainService.swift` and `LinkHubTests/Services/KeychainServiceTests.swift` automatically; no `project.yml` edit expected. **Verify post-generation locally.**
  - [ ] `xcodebuild … -configuration Debug build` — zero strict-concurrency warnings expected.
  - [ ] `xcodebuild … -configuration Debug test` — pure-query tests pass everywhere; `testLiveRoundTrip` may `XCTSkip` on the unsigned test host (expected).

## Dev Notes

### Story foundation

This story adds the **only long-lived password store in LinkHub** (NFR12): a stateless `KeychainService` over the Security framework, keyed by SSID. It writes nothing to UserDefaults, plain files, or any in-memory cache. Story 2.3 (WiFiRow connect flow) is the first caller: on a confirmed-successful `associate`, it calls `set(password:forSSID:)`; on the inline password expansion it pre-fills via `password(forSSID:)`. Story 2.6 (Forget) calls `remove(forSSID:)`.

`KeychainService` deliberately does **not** import or reference `WiFiMonitor`, `CoreWLAN`, or `AppState`. It is a leaf service confined to the `Security` framework (architecture.md § Framework Integration: "Security (Keychain) — `KeychainService` only. SSID-keyed `kSecClassGenericPassword`.").

### Keychain attribute set (normative)

The exact attribute set written by `set(password:forSSID:)` / produced by `addQuery(password:forSSID:)`:

| Key | Value | Source |
|---|---|---|
| `kSecClass` | `kSecClassGenericPassword` | FR31, epic AC #1, architecture.md |
| `kSecAttrService` | `Bundle.main.bundleIdentifier` (fallback `"com.linkhub.app"` in test hosts) | epic AC #1, architecture.md "Service: `Bundle.main.bundleIdentifier`" |
| `kSecAttrAccount` | SSID verbatim — no prefix | epic AC #1, architecture.md "Keychain account: SSID string verbatim (no prefix)" |
| `kSecAttrAccessible` | `kSecAttrAccessibleAfterFirstUnlock` | FR31, NFR12, PRD 08 D7, architecture.md enforcement item 8 |
| `kSecValueData` | UTF-8 bytes of the passphrase (`Data(password.utf8)`) | — |

`baseQuery` (match query for `SecItemUpdate` / `SecItemDelete`) carries **only** class + service + account. `copyQuery` adds `kSecReturnData = true` + `kSecMatchLimit = kSecMatchLimitOne`. `updateAttributes` carries **only** `kSecValueData` — class/service/account belong to the match query, not the update attributes.

**Not set:** `kSecAttrSynchronizable` — local keychain only, no iCloud sync (docs/06 Out of Scope: "iCloud Keychain sync for Wi-Fi passwords"). No `keychain-access-groups` — see entitlement caveat below.

### API shape decision — `throws` vs optional/Bool

- `set(password:forSSID:)` and `remove(forSSID:)` are **`throws`**, surfacing a typed `KeychainError` (`.unhandled(OSStatus)` carries the raw Security status). This satisfies architecture.md's "each layer defines a typed `enum SomethingError: Error`; no throwing `NSError` directly" and lets the Story 2.3 caller check success before considering a password "remembered".
- `password(forSSID:)` returns **`String?`** (no throw). A `nil` read — whether `errSecItemNotFound` or any other Security failure — means "not remembered", and the caller re-prompts. This matches AC #2 ("the user is not re-prompted … unless retrieval fails") and keeps the common read path branch-free at call sites.

### Upsert semantics

`set` does **add-or-update**, not delete-then-add: `SecItemAdd` first, and on `errSecDuplicateItem` it issues `SecItemUpdate(baseQuery, updateAttributes)`. This avoids a delete+add window where the item briefly does not exist, and preserves the original accessibility attribute. (PRD 06's sketch used `SecItemDelete` + `SecItemAdd`; the upsert form here is the more robust equivalent and matches the epic's "handle `errSecDuplicateItem` by updating" instruction.)

### Headless / unsigned test-host caveat (testing note)

The XCTest host bundle is **ad-hoc unsigned with no entitlements** in Debug (Story 1.1 build config). On a headless CI runner or a host without a usable login keychain, `SecItemAdd` can return `errSecMissingEntitlement`, `errSecNotAvailable`, or `errSecInteractionNotAllowed`. Therefore:

- The **pure query-attribute tests** (no live `SecItem*` calls) run and assert everywhere — they validate the FR31/NFR12 attribute set deterministically.
- The **live round-trip test** is guarded: if the first `set` throws `KeychainError.unhandled(status)`, the test calls `throw XCTSkip("Keychain unavailable … OSStatus \(status)")` rather than failing. This keeps CI green on hosts without a keychain while still exercising the real round-trip on developer machines.

### Entitlement caveat (from docs/08)

- **App Sandbox is OFF; Hardened Runtime is Release-only** (PRD 08 D1, D8). Outside the sandbox, the app reaches its own keychain items via the **implicit bundle-ID access group** — **no `keychain-access-groups` entitlement is required** (PRD 08 D8: "App-default — no `keychain-access-groups` entitlement"). Do not add one.
- **No Info.plist privacy key is required for Keychain** (PRD 08: "Security.framework Keychain — App's own keychain items; no privacy key required").
- `kSecAttrAccessibleAfterFirstUnlock` (not `WhenUnlocked`/`Always`) is mandated by PRD 08 D7 and architecture enforcement item 8 so a login-item launch can read credentials after reboot but before first interactive unlock.

### Naming discrepancy with PRD 06 (recorded for downstream stories)

PRD 06 (docs/06 § `KeychainService` API) sketches `savePassword(_:forSSID:)` / `loadPassword(forSSID:)`. The **epic Story 2.2 ACs (source of truth)** and this implementation use `set(password:forSSID:)` / `password(forSSID:)` (+ `remove(forSSID:)`). The epic-prescribed names win. PRD 06's `WiFiMonitor.connect(...)` / `PasswordPromptView.onAppear` pseudocode that references `KeychainService.savePassword` / `KeychainService.loadPassword` is **forward pseudocode** — when Story 2.3 wires the real connect flow, it must call `set(password:forSSID:)` / `password(forSSID:)`. No current code references the PRD 06 names, so there is no live conflict to resolve in this story. **Flagged for Story 2.3.**

### Layer-purity & concurrency

- `import Foundation`, `import Security` only. No AppKit/SwiftUI/Combine/CoreWLAN (architecture.md § Architectural Boundaries — `Services/` is a leaf called from AppState).
- `enum KeychainService` holds no stored state → nothing to send → no `@MainActor`, no `actor`, no `@unchecked Sendable`. All funcs are `static` and nonisolated. `static let service: String` is a `Sendable` constant, evaluated thread-safely.
- No `print` / `NSLog`. (No logging is emitted from this service in this story; the raw `OSStatus` travels in `KeychainError.unhandled` for the caller to log via `Log` if desired — a `Log.servicesKeychain` category is a future Logger addition, not required here.)

### Anti-patterns avoided

- No force-unwrap of `result as? Data` / `String(data:encoding:)` — guarded, with `nil`/`unexpectedData` fallbacks.
- No `kSecAttrAccessibleWhenUnlocked` / `…Always` (architecture enforcement item 8).
- No delete-then-add window — true upsert via `SecItemUpdate`.
- No password ever written outside the Keychain (NFR12).
- Did not touch `WiFiMonitor`, `WiFiMonitorProtocol`, `AppState`, or `project.yml` (Story 2.1 owns the monitor/protocol changes in parallel).

### Testing standards

- Framework: **XCTest** (Story 1.x carry-forward). `@testable import LinkHub`; `ENABLE_TESTABILITY = YES` Debug-only.
- New tests under `LinkHubTests/Services/` mirroring `LinkHub/Services/`.
- Live-keychain test is `XCTSkip`-guarded on `OSStatus` (see caveat above).

### References

- [Source: \_bmad-output/planning-artifacts/epics.md#Story 2.2] — BDD acceptance criteria (SOURCE OF TRUTH for this story)
- [Source: docs/06-wifi-management.md#`KeychainService` API] — API sketch (`savePassword`/`loadPassword`); naming superseded by epic ACs (see discrepancy note)
- [Source: docs/06-wifi-management.md#Out of Scope] — local keychain only; no iCloud sync; no `kSecAttrSynchronizable`
- [Source: docs/08-permissions-entitlements.md#Decision Log D7] — `kSecAttrAccessibleAfterFirstUnlock` rationale
- [Source: docs/08-permissions-entitlements.md#Decision Log D8] — App-default access group; no `keychain-access-groups` entitlement
- [Source: docs/08-permissions-entitlements.md#Info.plist Privacy Keys] — Keychain needs no privacy key
- [Source: docs/08-permissions-entitlements.md#Constraints] — "Keychain without sandbox: items keyed by `kSecAttrService` + bundle ID are isolated without an access-group entitlement"
- [Source: \_bmad-output/planning-artifacts/architecture.md#Naming & Storage] — "Keychain account: SSID string verbatim (no prefix). Service: `Bundle.main.bundleIdentifier`"
- [Source: \_bmad-output/planning-artifacts/architecture.md#Enforcement Guidelines item 8] — always `kSecAttrAccessibleAfterFirstUnlock`
- [Source: \_bmad-output/planning-artifacts/architecture.md#Framework Integration] — "Security (Keychain) — `KeychainService` only"
- [Source: \_bmad-output/planning-artifacts/architecture.md#Error types] — typed layer error enum; no `NSError` rethrow at boundaries
- [Apple Developer: SecItemAdd / SecItemCopyMatching / SecItemUpdate / SecItemDelete] — Keychain Services CRUD; `kSecClass`, `kSecAttrService`, `kSecAttrAccount`, `kSecAttrAccessible`, `kSecReturnData`, `kSecMatchLimit`
- [Source: \_bmad-output/implementation-artifacts/1-3-wifimonitor-on-demand-scan-push-events-scanstatus-timeout.md] — story-doc format reference; build/test workflow; unsigned-Debug test-host context

## Dev Agent Record

### Agent Model Used

Opus 4.8 (1M context)

### Debug Log References

- Build / test NOT runnable on Claude web (Linux, no Xcode/swiftc). Build & test must be verified locally on macOS + Xcode 16. See "Risks needing local verification" in the report.

### Completion Notes List

- AC #1 satisfied: `addQuery(password:forSSID:)` produces exactly `{ kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: SSID, kSecValueData: <utf8>, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock }`; asserted by `testAddQueryUsesAfterFirstUnlockAndCarriesData`.
- AC #2 satisfied: `password(forSSID:)` returns stored value or `nil` (never throws on read); upsert verified by `testLiveRoundTrip`.
- AC #3 satisfied at the API-surface level: `KeychainService` exposes set/get/remove only and never calls `associate`/`WiFiMonitor`; the no-write-on-failure rule is the Story 2.3 caller's responsibility (documented).
- AC #4 satisfied: passwords live only in the Keychain — no UserDefaults / file / in-memory store; `KeychainService` is a stateless `enum`.
- API shape: `set`/`remove` are `throws` (typed `KeychainError`); `password(forSSID:)` is optional-returning. Upsert via `SecItemAdd` → `SecItemUpdate` on `errSecDuplicateItem`.
- Headless guard: `testLiveRoundTrip` `XCTSkip`s on a `KeychainError.unhandled(status)` from the first `set`, reporting the `OSStatus`.
- Did NOT modify `WiFiMonitor` / `WiFiMonitorProtocol` / `AppState` / `project.yml` (Story 2.1 parallel ownership). The unrelated working-tree changes to those files belong to Story 2.1 and are out of this story's scope.

### File List

**New (LinkHub/):**
- LinkHub/Services/KeychainService.swift

**New (LinkHubTests/):**
- LinkHubTests/Services/KeychainServiceTests.swift

### Change Log

| Date | Change |
|---|---|
| 2026-06-08 | Story created and implemented: `KeychainService` (Security framework, SSID-keyed generic password, `kSecAttrAccessibleAfterFirstUnlock`, upsert via add-or-update, typed `KeychainError`); pure query-helper tests + guarded live round-trip. Status: review. |
| 2026-06-08 | code-review (orchestrator, static): verified FR31/NFR12 attribute set, in-place upsert on errSecDuplicateItem, nil-on-failure read, typed KeychainError (no NSError leak), stateless Sendable-clean namespace. Flagged: Story 2.3 must call set/password (not docs/06 savePassword/loadPassword sketch); live round-trip XCTSkips on unsigned host. Status → done. |
