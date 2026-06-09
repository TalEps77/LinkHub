# LinkHub — Local Verification & Release-Gate Checklist

> **Why this exists.** The implementation work for LinkHub is being authored in a Linux/web
> environment with no Xcode/swiftc (per `CLAUDE.md`). Every story's code + tests are written to
> Swift 6 strict-concurrency correctness by review, but the actual **build, test run, and
> hardware-dependent verification must execute on a Mac with Xcode 16**. This checklist is the
> single source of truth for those deferred gates, accumulated per story. A story is "done" in the
> sprint tracker when its code + tests + review are complete; it is **release-verified** only when
> the relevant rows below pass on real hardware.

## A. Build & test (run after every story; required before any release)

```bash
xcodegen generate
xcodebuild -project LinkHub.xcodeproj -scheme LinkHub -configuration Debug build      # zero warnings (NFR33)
xcodebuild -project LinkHub.xcodeproj -scheme LinkHub -configuration Release build    # zero strict-concurrency warnings
xcodebuild -project LinkHub.xcodeproj -scheme LinkHub -configuration Debug test       # all tests pass
```

- [ ] `xcodegen generate` picks up all new files (`UI/Panels/`, `UI/Components/`, `Services/`, `Network/`) via the recursive `path:` globs — no `project.yml` edit needed (verify post-generation).
- [ ] Debug build: **zero warnings** (NFR33).
- [ ] Release build: **zero Swift 6 strict-concurrency warnings/errors** (NFR33). The pre-existing Story 1.1 Release "isn't code signed but requires entitlements" warning is expected until signing is wired (Story 4.4).
- [ ] Full test suite green (no regressions across epics).

### Highest-risk compile spots flagged during web authoring (check these first if the build fails)
- [ ] `PopoverController` `@MainActor DismissBox` + `.environment(\.dismissPopover)` closure typing (`@MainActor () -> Void`) under strict concurrency (Story 1.5). Fallback: type the env value as plain `() -> Void` + `MainActor.assumeIsolated`.
- [ ] `WiFiSection.wifiPowerBinding` setter `Task { await appState.setWiFiPower(_) }` capture (Story 2.5).
- [ ] `EthernetMonitor` `@convention(c)` SCDynamicStore callback + `Unmanaged`/`SCDynamicStoreContext.info` pattern and the Sendable snapshot hop (Story 3.1).
- [ ] `WiFiRow` `@ViewBuilder body` if/else (context-menu attach) returns a single `some View` (Story 2.6).

## B. Accessibility — VoiceOver (Cmd+F5)

- [ ] Each `WiFiRow` reads the UX-DR22 combined label; decorative glyphs (checkmark, lock, globe, signal bars) are **not** separately announced (Story 1.4/1.6).
- [ ] Menu-bar icon reads UX-DR24: `"Wi-Fi connected, {SSID}, signal {strength}"` / `"Wi-Fi off"` / `"No network connection"` (Story 1.6).
- [ ] Announcements fire: disconnect → "No network connection"; power → "Wi-Fi turned on/off"; grant-after-denial → "Wi-Fi networks loading"; connect → "Connected to {SSID}"; Ethernet in/out → "Ethernet connected/disconnected" (Stories 1.5/1.6/2.3/3.5).
- [ ] `EthernetRow` reads UX-DR23 by state; state dots `accessibilityHidden` (Story 3.6).

## C. Accessibility — Reduce Motion (System Settings → Accessibility → Display)

- [ ] Wi-Fi list insert/remove: 0.2 s fade when off; instant when on (Story 1.4).
- [ ] Status-icon symbol change: 300 ms crossfade when off; instant when on (Story 1.6/3.4).
- [ ] Row expand/collapse + section reorder: 250 ms when off; instant when on (Story 2.3/3.5).
- [ ] Obtaining-state dot pulse: 1.2 s loop when off; static when on (Story 3.3).

## D. Functional — Wi-Fi (use `LINKHUB_MOCK_WIFI=1` where hardware is unavailable)

- [ ] Scan-on-open populates the list; connected row first with checkmark + semibold (Story 1.4).
- [ ] Location denied → `LocationDeniedView`; "Open Privacy Settings" dismisses popover + opens the pane; grant auto-retries scan without restart (Story 1.5).
- [ ] Open-network single-tap connect; WPA inline password expand → connect; wrong password → "Incorrect password" caption, field cleared, stays expanded (Story 2.3).
- [ ] "Other Network…" hidden-network join form (in-popover, no sheet) (Story 2.4).
- [ ] Power toggle flips the real radio; off → "Wi-Fi: Off", list hidden, association dropped (Story 2.5).
- [ ] Captive network connect → default browser opens `captive.apple.com` (Story 2.5).
- [ ] Right-click a known network → Forget / Open in Settings; unknown rows show no menu; Forget clears Keychain + opens Wi-Fi settings (Story 2.6).
- [ ] Keychain: password persisted only on successful connect; re-join does not re-prompt (Story 2.2/2.3).

## E. Functional — Ethernet (Epic 3; requires a USB-C/Thunderbolt/dock Ethernet adapter)

- [ ] Cable in → icon morphs to `cable.connector` within 1.5 s; `EthernetSection` promoted above Wi-Fi (Story 3.3/3.4).
- [ ] Four interface states render with dot + text label (active/obtaining/dhcpTimeout/noLink) (Story 3.3).
- [ ] Cable out → 1.5 s grace before section hides; transient unplug does not flicker (Story 3.5).
- [ ] Multiple interfaces: top 2 inline, "+ N more in Settings…" overflow → opens Network Settings pane (Story 3.6).
- [ ] Survives sleep/wake, router reset, dock reconnect, VPN toggle (Story 3.5, NFR11).

## F. Performance / reliability — Instruments (Apple Silicon)

- [ ] Popover first paint ≤200 ms cold / ≤100 ms warm (NFR2) — Time Profiler from launch to first open (Story 1.4).
- [ ] Idle (panel closed 60 s): resident memory ≤80 MB, 60 s avg CPU ≤0.5% (FR48/FR49) — **Epic 1 baseline** (Story 1.6).
- [ ] Epic 2 regression: same budget after 10 connect/disconnect/forget cycles (Story 2.6).
- [ ] Epic 3 regression: same budget after 10 cable in/out cycles + dock reconnect + sleep/wake; 1-hour Allocations/Leaks shows zero LinkHub leaks (Story 3.6, NFR8).
- [ ] **Story 4.7 final pass:** 1-hour Allocations + Leaks + Time Profiler with induced traffic; ≤80 MB / ≤0.5% CPU / zero leaks; ≤±5% vs. prior epic baselines (Story 4.7) — **this story is verification-only and cannot be executed without hardware.**

## G. Distribution (Epic 4 — requires Developer ID cert, notary credentials, signing Mac)

- [ ] Sparkle 2 SPM dependency resolves; `SUPublicEDKey` / feed URL set in Info.plist (Story 4.3).
- [ ] `scripts/notarize.sh`: archive → export (Developer ID) → `notarytool submit --wait` → `stapler staple`; `codesign --verify --deep --strict` valid; Hardened Runtime + Location entitlement only (Story 4.4, NFR13/15/17).
- [ ] `scripts/make-dmg.sh`: `LinkHub-{version}.dmg` with `/Applications` symlink; signature + staple intact; Gatekeeper-clean on a clean Mac (Story 4.5, FR51/FR52).
- [ ] `scripts/update-appcast.sh`: EdDSA-signed `<item>` appended; GitHub Pages serves the feed; Sparkle verifies signature and rejects mismatches (Story 4.6, NFR16).

## H. Spec-divergence reconciliation (decisions logged during implementation)

These were resolved in favor of the epic/UX ACs during web authoring; confirm or formally reconcile in the PRDs:
- [ ] Section header `.caption` UPPERCASE vs PRD 04 D12 `.subheadline` mixed-case (Story 1.4).
- [ ] Signal bars: custom `RoundedRectangle` (PRD 04 D6) vs epic "SF Symbol" — `wifi.0…3` are macOS 14+ (Story 1.4).
- [ ] Empty state text-only `.callout` vs PRD 04 D17 `wifi.slash` icon (Story 1.4).
- [ ] `isPowered` (AC) modeled as the existing `isEnabled` flag (Story 2.5).
- [ ] "Known network" defined as LinkHub-remembered (Keychain) — no public system known-networks API (Story 2.6).
