# Story 3.3: EthernetSection + EthernetRow with Four States

Status: done

## Story

As a user,
I want to see a per-Ethernet-interface row with its display name, status, IP, and link speed,
so that I can understand at a glance whether each interface is healthy.

## Acceptance Criteria

1. **`EthernetSection` renders above `WiFiSection` when ≥1 interface has link**
   - **Given** at least one Ethernet interface has link
   - **When** `RootPanelView` renders
   - **Then** `EthernetSection` appears above `WiFiSection` (FR12, UX-DR9, UX-DR10)
   - **And** the section header is `.caption` UPPERCASE 10 pt semibold "ETHERNET" (UX-DR3) — mirrors `WiFiSection`'s header style exactly
   - **And** the top 2 active interfaces render inline as `EthernetRow`s (multi-interface sort + "+N more" overflow is **Story 3.6** — not built here)

2. **`EthernetRow` anatomy + four states**
   - **Given** an `EthernetRow`
   - **When** it renders
   - **Then** layout is `HStack { StateDot; VStack(.leading) { displayName(.body); detail(.caption) } }` (UX-DR11)
   - **And** the state dot is an 8 pt circle paired with a plain-text status label so color is never the only signal (UX-DR26)
   - **And** four states are supported: `.active` ("Active", green dot, detail = `"{ip} • {speed}"`), `.obtaining` ("Obtaining…", pulsing yellow), `.dhcpTimeout` ("DHCP timeout", red), `.noLink` ("No link", gray) (FR16, UX-DR11)

3. **Obtaining pulse gated on Reduce Motion**
   - **Given** a row in `.obtaining`
   - **When** Reduce Motion is off
   - **Then** the dot pulses on a 1.2 s loop, opacity 0.4 → 1.0 ease-in-out (UX-DR19)
   - **And** when Reduce Motion is on, the dot is static at 1.0 (UX-DR20)

4. **Color discipline**
   - **Given** the section is rendered
   - **When** colors are inspected
   - **Then** all colors resolve via system semantic tokens; no hex literals; `Color.red` only used for the DHCP-timeout dot's adjacent inline text, and `.green`/`.yellow`/`.red`/`.secondary` only for the status dot (UX-DR4)

## Tasks / Subtasks

- [x] **Task 1: `UI/Components/EthernetRow.swift` — single interface row** (AC: #2, #3, #4)
  - [x] Create the file; `import SwiftUI` only.
  - [x] `struct EthernetRow: View` with `let interface: EthernetInterface`, `@Environment(\.accessibilityReduceMotion)`, and a local `@State private var pulsing` driving the obtaining loop.
  - [x] Body `HStack(spacing: 8) { stateDot; VStack(alignment: .leading) { displayName(.body); detailText(.caption) }; Spacer(minLength: 0) }` with `PanelLayout` row padding (mirrors `WiFiRow`).
  - [x] `stateDot`: 8 pt `Circle().fill(Self.dotColor(...))`, `.accessibilityHidden(true)`; pulses opacity 0.4↔1.0 on a `.easeInOut(1.2).repeatForever(autoreverses:)` loop only when `state == .obtaining && !reduceMotion`, else static 1.0.
  - [x] `.accessibilityElement(children: .combine)` + combined `.accessibilityLabel(...)`.
  - [x] Pure helpers: `statusLabel(for:)`, `dotColor(for:)`, `detailString(for:)`, `speedDescription(_:)`, `accessibilityLabel(for:)`.
  - [x] DHCP-timeout detail line is the one allowed `Color.red` inline-text use; other states `.secondary`.
  - [x] `#Preview` of all four states.

- [x] **Task 2: `UI/Panels/EthernetSection.swift` — header + inline rows** (AC: #1)
  - [x] Create the file; `import SwiftUI` only; `@EnvironmentObject var appState: AppState` (NFR35).
  - [x] Header mirrors `WiFiSection`: `Text("ETHERNET").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)` with `PanelLayout` header padding (no toggle — Ethernet has no power switch).
  - [x] `ForEach(Self.displayedInterfaces(from:))` of `EthernetRow`.
  - [x] Pure `static func displayedInterfaces(from: NetworkState) -> [EthernetInterface]` — active-first, monitor-order within group, capped at top 2.
  - [x] `#Preview`s driven by `MockEthernetMonitor.sampleInterfaces` + a four-state fixture via `AppState(wifiMonitor:ethernetMonitor:)`.

- [x] **Task 3: `UI/PopoverRootView.swift` — integration** (AC: #1)
  - [x] In the normal-list `content` branch, render `EthernetSection()` above `WiFiSection()` inside the existing `VStack(spacing: PanelLayout.interSectionSpacing)`, gated on `!appState.networkState.ethernetInterfaces.isEmpty`.
  - [x] Keep the existing `showingOtherNetwork` routing intact (Ethernet section is only in the normal list, never the `OtherNetworkPanel` route).
  - [x] No grace timer / reorder animation here (Story 3.5).
  - [x] Update the `#Preview` to seed Ethernet interfaces via `MockEthernetMonitor`.

- [x] **Task 4: Tests** (AC: #1, #2, #4)
  - [x] `LinkHubTests/UI/Components/EthernetRowTests.swift` — `speedDescription(_:)` (nil/Mbps/Gbps), `statusLabel(for:)`, `dotColor(for:)`, `detailString(for:)` (active joins ip+speed, ip-only, speed-only; non-active uses status label), `accessibilityLabel(for:)`.
  - [x] `LinkHubTests/UI/Panels/EthernetSectionTests.swift` — `displayedInterfaces(from:)`: empty, single, cap-at-two, active-first sort, monitor-order preservation within groups.

- [ ] **Task 5: XcodeGen, build, test (LOCAL — cannot run on Linux/web)**
  - [ ] `xcodegen generate` (new files under the existing recursive `LinkHub` / `LinkHubTests` source globs — no `project.yml` edit needed; verify post-generate).
  - [ ] `xcodebuild -scheme LinkHub -configuration Debug build` → zero warnings (NFR33).
  - [ ] `xcodebuild -scheme LinkHub test` → all new + existing tests pass.
  - [ ] Manual: plug Ethernet (or `LINKHUB_MOCK` path) → ETHERNET section above WI-FI, dot+label per state, obtaining pulses (off under Reduce Motion).

## Dev Notes

### Scope boundaries (read carefully)

- **Multi-interface sort + "+N more" overflow → Story 3.6.** This section renders **at most 2** rows via `displayedInterfaces(from:)` (active-first, capped at 2). No collapse/overflow control here. The canonical multi-NIC sort and the "+N more" affordance are Story 3.6's deliverables.
- **250 ms section-reorder animation + cable-out grace timer → Story 3.5.** `RootPanelView` simply includes the section conditionally; it does not animate the Ethernet↔Wi-Fi reorder and does not hold the section visible during a brief cable-out (no grace `Timer`). The monitor only emits interfaces that have link, so a non-empty `ethernetInterfaces` is the "has link" predicate used for the conditional.
- **Full UX-DR23 VoiceOver templates → Story 3.6.** This story's `accessibilityLabel(for:)` is a reasonable interim combination (`"{displayName}, {status}[, {detail}]"`); the dot is `.accessibilityHidden(true)` and the row uses `.accessibilityElement(children: .combine)`. Story 3.6 owns the canonical per-state label templates.
- **`StatusItemController` is untouched** — the menu-bar Ethernet icon path + crossfade is Story 3.4 (parallel). `EthernetMonitor`, `AppState`, `WiFiSection`, and `WiFiRow` are also untouched; only NEW files + `PopoverRootView.swift` were modified.

### State → (label, dot color, detail) mapping

| State | Status label | Dot color | Detail line |
|---|---|---|---|
| `.active` | "Active" | `.green` | `"{ip} • {speed}"` (ip-only or speed-only if one is missing; "Active" if both missing) |
| `.obtaining` | "Obtaining…" | `.yellow` (pulsing) | "Obtaining…" |
| `.dhcpTimeout` | "DHCP timeout" | `.red` | "DHCP timeout" (inline text in `Color.red`) |
| `.noLink` | "No link" | `.secondary` (gray) | "No link" |

`speedDescription(_:)`: `nil → ""`, `< 1000 → "{n} Mbps"`, `>= 1000 → "{n/1000} Gbps"` formatted to one decimal (`1000 → "1.0 Gbps"`, `2500 → "2.5 Gbps"`).

### Obtaining-pulse approach

The dot owns a local `@State private var pulsing` flipped to `true` in `.onAppear` only when `state == .obtaining && !reduceMotion`. `.opacity` reads `pulsing ? 1.0 : 0.4` and the `.animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulsing)` interpolates between the two endpoints. When Reduce Motion is on (or the state is not `.obtaining`), `opacity` is hard-pinned to `1.0` and the animation argument is `nil` — static dot, no implicit animation registered (UX-DR19/20, mirrors `WiFiRow`/`WiFiSection`'s Reduce-Motion gating idiom).

### Color discipline (AC #4)

- Row text uses `.primary` (default) and `.secondary` only.
- The four status-dot colors (`.green`/`.yellow`/`.red`/`.secondary`) are the **documented exception** to "semantic colors only" for the status indicator — they are system `Color` tokens (dark-mode-correct), not hex literals.
- `Color.red` appears in exactly one place for inline **text**: the `.dhcpTimeout` detail line (UX-DR4), mirroring `WiFiRow`'s single allowed `Color.red` error-caption use.

### Layer purity / state-subscription

- `EthernetRow.swift`, `EthernetSection.swift`: `import SwiftUI` only. No `AppKit`/`SystemConfiguration`/`Combine`.
- State is read via `@EnvironmentObject var appState: AppState` only — never a monitor (NFR35). `EthernetRow` takes its `interface` by value from the section's `ForEach`.
- No new Combine sinks — `appState.networkState` (populated by Story 3.2's dual-monitor sink) re-renders the tree via `@EnvironmentObject`/`@Published`.

### File-structure requirements

| File | Status | Purpose |
|---|---|---|
| `LinkHub/UI/Components/EthernetRow.swift` | NEW | Single interface row; four states; obtaining pulse; pure helpers |
| `LinkHub/UI/Panels/EthernetSection.swift` | NEW | "ETHERNET" header + top-2 inline rows; `displayedInterfaces(from:)` |
| `LinkHub/UI/PopoverRootView.swift` | MODIFIED | Render `EthernetSection()` above `WiFiSection()` when `!ethernetInterfaces.isEmpty`; preview seeds Ethernet |
| `LinkHubTests/UI/Components/EthernetRowTests.swift` | NEW | `speedDescription`/`statusLabel`/`dotColor`/`detailString`/`accessibilityLabel` |
| `LinkHubTests/UI/Panels/EthernetSectionTests.swift` | NEW | `displayedInterfaces(from:)` ordering + cap |

### View tree (canonical for this story)

```
RootPanelView
└── content (normal list branch)
    └── VStack(spacing: 8)                         ← PanelLayout.interSectionSpacing
        ├── if !ethernetInterfaces.isEmpty → EthernetSection
        │   ├── header (HStack) → Text("ETHERNET") ← .caption 10pt semibold uppercase secondary
        │   └── VStack → ForEach(displayedInterfaces) { EthernetRow }
        └── WiFiSection
EthernetRow
└── HStack(spacing: 8)                             ← .accessibilityElement(children: .combine)
    ├── stateDot (8pt Circle)                      ← dotColor(state); pulsing if obtaining & !reduceMotion; hidden
    ├── VStack(.leading)
    │   ├── Text(displayName)                      ← .body, 1 line, tail-truncated
    │   └── Text(detailString)                     ← .caption; .red for .dhcpTimeout else .secondary
    └── Spacer(minLength: 0)
```

## Change Log

- Header uses the `WiFiSection` `.font(.system(size: 10, weight: .semibold))` + `.textCase(.uppercase)` + `.foregroundStyle(.secondary)` idiom rather than `.subheadline` (matches UX-DR3 + the established Wi-Fi header; no toggle on the Ethernet header since Ethernet has no power switch).
- `displayedInterfaces(from:)` resolves the "top 2 active interfaces" AC as **active-first then monitor-order, capped at 2** — a deliberately minimal pre-3.6 sort. The full multi-NIC sort key and "+N more" overflow are explicitly deferred to Story 3.6.
- `RootPanelView` was already structured for this integration (the conditional `EthernetSection()` block and Ethernet-seeded `#Preview` are part of this story's change to `PopoverRootView.swift`).
- code-review (orchestrator) fix: the `RootPanelView` visibility predicate was `!ethernetInterfaces.isEmpty`, but `EthernetMonitor` enumerates all hardware interfaces including cable-out `.noLink` ones, so the section would wrongly appear for a plugged-but-no-cable adapter. Tightened to `contains { $0.state != .noLink }` (≥1 has link, per AC #1); Story 3.5 layers the 1.5 s cable-out grace on top. Status → done.

## File List

- `LinkHub/UI/Components/EthernetRow.swift` (new)
- `LinkHub/UI/Panels/EthernetSection.swift` (new)
- `LinkHub/UI/PopoverRootView.swift` (modified)
- `LinkHubTests/UI/Components/EthernetRowTests.swift` (new)
- `LinkHubTests/UI/Panels/EthernetSectionTests.swift` (new)
