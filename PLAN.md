# LinkHub — Master Plan

> **LinkHub** is a macOS menu bar app that replaces the standard Wi-Fi menu bar item with a
> unified control center for Wi-Fi and Ethernet. When no Ethernet is present it behaves
> identically to the system Wi-Fi menu. When Ethernet is active the icon switches to an
> Ethernet-style icon and the panel presents Ethernet status/controls first, followed by
> Wi-Fi networks and controls.

**Repo:** `TalEps77/LinkHub`  
**PRD folder:** `docs/`  
**Stack:** Swift, SwiftUI / AppKit, CoreWLAN, SystemConfiguration, macOS 13+

---

## How This Plan Works

Every row in the task table below represents a **planning session**, not a coding task.
The output of each session is a PRD file saved to `docs/`. No Swift code is written until
all required PRDs are marked ✅ Done.

---

## Status Key

| Symbol | Meaning |
|--------|---------|
| ⬜ | Not Started |
| 🔵 | In Progress |
| 🔍 | In Review |
| ✅ | Done |
| 🚫 | Blocked |

---

## Planning Sessions

| # | Status | Title | PRD File | What the PRD Must Decide |
|---|--------|-------|----------|--------------------------|
| 01 | ⬜ | Project & Architecture Setup | `docs/01-project-architecture.md` | Xcode project structure, minimum macOS deployment target, Swift version, module/folder layout, dependency strategy (SPM), build configurations, scheme setup, `.gitignore` and repo conventions |
| 02 | ⬜ | Menu Bar Integration | `docs/02-menubar-integration.md` | `NSStatusItem` lifecycle, `NSMenu` vs. custom `NSPanel` popover approach, icon asset pipeline (SF Symbols vs. custom assets), icon-swap trigger contract (Wi-Fi ↔ Ethernet), accessibility labels |
| 03 | ⬜ | Network Detection & Observation | `docs/03-network-detection.md` | Frameworks for detection (`CoreWLAN` for Wi-Fi, `SystemConfiguration`/`SCDynamicStore` for Ethernet), interface enumeration strategy, polling vs. push notifications, event debounce, edge cases (multiple adapters, USB-C dongles, VPNs) |
| 04 | ⬜ | Panel UI Architecture | `docs/04-panel-ui-architecture.md` | Technology choice (SwiftUI in `NSPanel`/`NSPopover` vs. AppKit), panel sizing, section layout contract (Ethernet on top, Wi-Fi below), dark/light mode, open/close animations |
| 05 | ⬜ | Ethernet Status & Controls | `docs/05-ethernet-controls.md` | Info displayed per interface (IP, link speed, status), controls exposed (toggle, open Network Settings), multiple adapter handling, refresh cadence, empty/error states |
| 06 | ⬜ | Wi-Fi Network Management | `docs/06-wifi-management.md` | Scanning cadence, network list fields (SSID, signal, security), connect/disconnect/forget flows, password prompt + Keychain, hidden networks, captive portals, error messaging, `CoreWLAN` API surface |
| 07 | ⬜ | State & Data Management | `docs/07-state-data-management.md` | Central state model design, concurrency model (MainActor/Combine/async-await), how network services publish into shared state, persistence needs (preferences), memory/CPU budget for a persistent menu bar app |
| 08 | ⬜ | Permissions, Entitlements & Privacy | `docs/08-permissions-entitlements.md` | Required entitlements, location permission for Wi-Fi scanning (macOS 10.15+), sandbox vs. hardened runtime trade-offs, `Info.plist` keys, first-launch permission UX |
| 09 | ⬜ | Distribution & Release | `docs/09-distribution-release.md` | Distribution channel (Mac App Store vs. direct), code signing (Developer ID vs. Mac Distribution), notarization workflow, Sparkle auto-update, versioning scheme, release checklist |

---

## PRD Dependency Graph

```
01 (Architecture)
 ├── 02 (Menu Bar)
 ├── 03 (Network Detection)
 │    ├── 05 (Ethernet Controls)
 │    ├── 06 (Wi-Fi Management)
 │    └── 07 (State & Data)
 ├── 04 (Panel UI)  ← also depends on 02
 └── 08 (Permissions)  ← also depends on 03, 06
09 (Distribution) ← depends on 01, 08
```

PRDs 05, 06, and 07 may be drafted in parallel once 03 is done.  
PRD 04 may be drafted in parallel with 03 once 01 and 02 are done.

---

## Session Checklist (what "Done" means for any PRD)

Before marking a PRD ✅, confirm it covers:

- [ ] Problem statement — what question does this PRD answer?
- [ ] Decision log — every meaningful choice recorded with rationale
- [ ] Constraints — OS version floor, framework limitations, Apple policy
- [ ] Out of scope — explicit list of what this PRD deliberately defers
- [ ] Open questions — unresolved items to revisit before coding starts
- [ ] References — Apple docs links, WWDC sessions, related projects

---

## Overall Progress

| Phase | PRDs | Status |
|-------|------|--------|
| Foundation | 01, 02, 03 | ⬜ ⬜ ⬜ |
| Features | 04, 05, 06, 07 | ⬜ ⬜ ⬜ ⬜ |
| Delivery | 08, 09 | ⬜ ⬜ |

**Total: 0 / 9 PRDs complete**
