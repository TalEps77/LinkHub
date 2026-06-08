# Deferred Work

## Deferred from: code review of story-1.1 (2026-05-09)

- LinkHubTests Release config deviates from spec table — `CODE_SIGN_IDENTITY="-"` and `ENABLE_HARDENED_RUNTIME=NO` instead of `""` / `YES`. Harmless for `xcodebuild test`; revisit when CI signing wired in Story 4.4. [LinkHub.xcodeproj/project.pbxproj:349-351, project.yml:95-96]
- `LinkHubTests/PlaceholderTests.swift` is `XCTAssertTrue(true)` — replace with a meaningful test once Story 1.3 adds real coverage. Spec acknowledges placeholder.
- `NSSupportsAutomaticTermination=NO` not declared in Info.plist — macOS may auto-terminate idle `LSUIElement` apps. Re-evaluate in Story 1.2 when `NSStatusItem` is wired.
- `.gitignore` blanket `.claude/` blocks committing legitimate shared team config (e.g., `.claude/settings.json`). Tighten if/when team config needs sharing.
- `project.yml` and `LinkHub.xcodeproj/project.pbxproj` both committed — spec AC7 mandates committing pbxproj, but with XcodeGen as source of truth, regen drift is possible. Document workflow or consider gitignoring pbxproj in a future story.

## Deferred from: code review of story-1.2 (2026-05-09)

- `AppState.connectionMode` is a separate `@Published` alongside `networkState.mode` with no production-side sync invariant. Spec Task 1 (line 64) mandates the field; Story 1.3 wires the CombineLatest sink and is the natural place to enforce mirroring or eliminate one of the two. [LinkHub/State/AppState.swift:7]
- `AppStateTests` and `StatusItemControllerTests` both touch `UserDefaults.standard` for `launchAtLogin`. Under Xcode default parallel test execution, `setUp`/`tearDown` of one test can clobber another's reads. Spec line 361 punts to a `UserDefaults(suiteName:)` migration if it gets noisy. [LinkHubTests/State/AppStateTests.swift]
- `testAnnounceOnDisconnectionTransitionOnly` does not assert the actual `NSAccessibility.post` announcement contract — comment in test admits "we cannot easily intercept ... in unit tests". Spec line 365 prescribes injecting an announcement closure on `StatusItemController` for spy-based assertion; defer until D15 regression risk warrants the production-API change. [LinkHubTests/MenuBar/StatusItemControllerTests.swift:48-61]

## Deferred from: code review of story-1.3 (2026-05-09)

- `isCaptive` hardcoded `false` in `WiFiMonitor.performScan` and `makeConnectedNetwork` — Story 2.5 owns FR25 captive marker. Captive detection requires NEHotspotHelper or active probe; out of scope here.
- `requiresPassword: security != .none && security != .enterprise` — matches the spec text exactly but semantically misleading: enterprise networks require credentials too. Story 2.x connect/password UX is the correct place to disambiguate "shows password field" vs "requires credentials". Rename or split when wiring connect path.
- `connectedNetwork.id == bssid` and the scan-result entry for the same BSSID share an `id` — `WiFiSection` (Story 1.4) merges/dedupes; address there to avoid SwiftUI `Identifiable` runtime warnings.
- Wi-Fi power-off VoiceOver announcement (UX-DR25 from PRD 02 / Story 1.6) — `StatusItemController.announceIfDisconnected` only fires on disconnect transition, not on power-off / hardware-unavailable transitions. Story 1.6 owns the VoiceOver-label expansion; thread power-off into the announcement set there.
- `LSUIElement = true` is not provable from this diff (`LinkHub/Info.plist` is untracked). Story 1.1 is the canonical owner of Info.plist content; verify post-`xcodegen generate` and confirm the menu-bar-only invariant before Story 1.4 panel UI lands.
- Sparkle scripts (`scripts/notarize.sh`, `scripts/make-dmg.sh`, `scripts/update-appcast.sh`) referenced in `_bmad-output/planning-artifacts/epics.md` (lines ~1639/1663/1686) are not present in the repo. Epic 4.4–4.6 territory; flag at Sprint Planning when Epic 4 enters scope.
