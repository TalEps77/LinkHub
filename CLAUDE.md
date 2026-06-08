# CLAUDE.md — LinkHub

macOS menu-bar app: unified Wi-Fi + Ethernet control center, replacing the system Wi-Fi menu. Swift 6 / SwiftUI + AppKit, CoreWLAN + SystemConfiguration, macOS 13+.

## Build / test

Project is generated with **XcodeGen** from `project.yml` — `LinkHub.xcodeproj` is a build artifact, regenerate it; don't hand-edit.

```bash
xcodegen generate          # regenerate LinkHub.xcodeproj from project.yml
open LinkHub.xcodeproj      # or build from CLI:
xcodebuild -project LinkHub.xcodeproj -scheme LinkHub -configuration Debug build
xcodebuild -project LinkHub.xcodeproj -scheme LinkHub test
```

Requires **macOS + Xcode 16**. Cannot build, compile, or test on Claude web (Linux, no Xcode/swiftc). On web: planning, docs, and code authoring only — verify builds locally.

Swift strict concurrency is **complete** — write actor-safe code.

## Layout

- `LinkHub/` — app source: `App/`, `MenuBar/`, `Network/` (+ `Models/`), `State/`, `UI/` (`Components/`, `Panels/`, `Windows/`), `Services/`, `Utilities/`.
- `LinkHubTests/` — XCTest, mirrors source tree. `Network/MockWiFiMonitor.swift` + `WiFiMonitorProtocol.swift` enable testing without real hardware.
- `docs/01..09` — per-area PRDs (architecture, menu-bar, network detection, panel UI, ethernet, wifi, state, permissions, distribution).
- `_bmad-output/planning-artifacts/` — PRD, architecture, epics, UX spec. `_bmad-output/implementation-artifacts/` — sprint/story output.
- `PLAN.md` — progress tracker.

## Planning workflow (BMad)

This project uses the **BMad** skill suite (create-prd, create-epics-and-stories, dev-story, code-review, etc.). Runtime lives in tracked `_bmad/` (config + `scripts/resolve_config.py`, needs `python3`). The skills themselves live in `.claude/skills/` which is **gitignored** — they do NOT travel with the repo. On Claude web they must be installed at the account/plugin level.

## Conventions

- Match existing Swift style. Surgical changes — every changed line traces to the request.
- Sparkle 2 (auto-update) is planned via SPM in Story 4.3 — `.build/ .swiftpm/ Packages/` ignores are pre-staged (commented) in `.gitignore`.
- Never commit secrets: `.env`, `secrets.plist`, `*.key`, `*.pem` are gitignored.

## Global behavioral rules (ported from ~/.claude, which does not travel to web)

- **Think before coding** — state assumptions; if multiple interpretations, surface them; push back when a simpler approach exists; ask when unclear.
- **Simplicity first** — minimum code that solves it; no speculative abstractions, config, or error handling for impossible cases.
- **Surgical changes** — touch only what the task needs; don't refactor or reformat adjacent code; mention dead code, don't delete it unasked.
- **Goal-driven** — turn tasks into verifiable checks (write the failing test, then pass it); state a brief plan with per-step verification.
- **Artifact rule** — every persisted artifact >~50 lines or with tables/diagrams gets emitted as BOTH `<name>.md` (source of truth) and `<name>.html` (self-contained render, inline CSS, no external deps). Chat answers stay plain text.
