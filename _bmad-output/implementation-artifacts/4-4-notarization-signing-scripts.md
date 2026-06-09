# Story 4.4: Notarization + Signing Scripts

Status: done

## Story

As a developer,
I want a reproducible script that code-signs, notarizes, and staples the LinkHub.app,
so that distribution artifacts are Gatekeeper-clean and the release process is one command.

## Acceptance Criteria

1. **Developer ID export from a Release archive**
   - **Given** a Release archive
   - **When** export runs
   - **Then** `xcodebuild archive` produces an `.xcarchive` and `xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist` produces `LinkHub.app` (NFR13, NFR15)
   - **And** `ExportOptions.plist` is configured for Developer ID export (`method` = `developer-id`), not Mac App Store

2. **notarytool submit + staple**
   - **Given** the exported `LinkHub.app`
   - **When** `scripts/notarize.sh` runs
   - **Then** the script invokes `xcrun notarytool submit ... --keychain-profile linkhub-notary --wait` and returns success (NFR14)
   - **And** on success, `xcrun stapler staple LinkHub.app` runs and the staple is verified

3. **Signature + entitlements verification**
   - **Given** the signed and notarized `LinkHub.app`
   - **When** `codesign --verify --deep --strict --verbose=2 LinkHub.app` runs
   - **Then** the signature is valid with a Developer ID Application certificate (NFR13)
   - **And** `codesign --display --entitlements -` shows Hardened Runtime enabled and the Location entitlement only (NFR15, NFR17)

4. **Gatekeeper-clean for end users**
   - **Given** an end-user downloads and opens the app
   - **When** Gatekeeper evaluates it
   - **Then** no warning or block dialog appears (FR52)

## Tasks / Subtasks

- [x] **Task 1: `ExportOptions.plist` (repo root) for Developer ID export** (AC: #1)
  - [x] `method` = `developer-id`, `signingStyle` = `automatic`, `destination` = `export`, `teamID` = `__TEAMID__` placeholder
  - [x] No Team ID committed — placeholder is substituted at runtime by `notarize.sh` into a temp copy (so the repo never carries a real Team ID)
  - [x] Header comment cross-references docs/09 § Code Signing Setup
- [x] **Task 2: `scripts/notarize.sh` — archive → export → notarize → staple → verify** (AC: #1, #2, #3, #4)
  - [x] `#!/usr/bin/env bash`, `set -euo pipefail`, executable (`chmod +x`)
  - [x] Parameterized via env vars (`LINKHUB_TEAM_ID` required; `LINKHUB_NOTARY_PROFILE`/`SCHEME`/`CONFIGURATION`/`PROJECT`/`BUILD_DIR` overridable). **No secrets hardcoded** — the notary credential lives in the `linkhub-notary` Keychain profile; the Developer ID cert lives in the login Keychain
  - [x] Preflight: requires `LINKHUB_TEAM_ID`, `xcodebuild`/`xcrun`, the `.xcodeproj`, `ExportOptions.plist`, and a reachable `linkhub-notary` profile; fails loudly otherwise
  - [x] Step 1 — `xcodebuild archive` → `build/LinkHub.xcarchive` (passes `DEVELOPMENT_TEAM`/`CODE_SIGN_STYLE=Automatic`)
  - [x] Step 2 — `xcodebuild -exportArchive -exportOptionsPlist <temp>` → `build/export/LinkHub.app`
  - [x] Step 3 — `ditto -c -k --keepParent` → `build/LinkHub.zip` (notarytool input)
  - [x] Step 4 — `xcrun notarytool submit ... --keychain-profile "$NOTARY_PROFILE" --wait`; on non-`Accepted` verdict, fetches `notarytool log <id>` and dies
  - [x] Step 5 — `xcrun stapler staple` the app
  - [x] Step 6 — verify: `stapler validate`, `codesign --verify --deep --strict --verbose=2`, echo signing authority + entitlements (expect Developer ID Application, Hardened Runtime flag, Location entitlement only), `spctl --assess --type execute -vvv`
  - [x] Clear progress output (`==>`/`OK`/`ERROR`); every step fails loudly
- [ ] **Task 3: Local execution (maintainer gate — NOT runnable here)**
  - [ ] Run on a signing Mac with Xcode 16, a Developer ID Application certificate in the login Keychain, and the `linkhub-notary` notarytool profile; confirm `status: Accepted` and a Gatekeeper-clean app
  - **GATE:** requires a signing Mac + Developer ID cert + App Store Connect API key (notary credentials). Cannot run on Linux/web (no Xcode, no signing identity, no Apple notary access).

## Dev Notes

### Tool / command choices (and why)

| Concern | Choice | Rationale (docs/09) |
|---|---|---|
| Distribution channel | Developer ID direct | MAS sandbox blocks `CWWiFiClient.associate(...)` (PRD 08); decision #1/#2 |
| Export method | `developer-id` in `ExportOptions.plist` | Decision #2 — `Mac App Distribution` certs produce Gatekeeper-rejected binaries outside MAS |
| Provisioning profile | None | Decision #3 — Developer ID uses cert + entitlements + identity only |
| Notarization tool | `xcrun notarytool submit --wait` | Decision #4 — `altool` removed in Xcode 14; notarytool is the only supported path, minutes not hours |
| Notary auth | App Store Connect API key in `linkhub-notary` Keychain profile | Decision #5 — non-interactive, CI-friendly, no Apple ID password stored |
| Stapling | Always `xcrun stapler staple` | Decision #6 — embeds the ticket for OFFLINE Gatekeeper (critical: LinkHub may launch with no connectivity) |

### Secrets handling

- The Team ID is the only deployment-specific value; it is injected at runtime from `LINKHUB_TEAM_ID` into a `mktemp` copy of `ExportOptions.plist` (removed on exit via `trap`). The committed plist keeps the `__TEAMID__` placeholder.
- The Developer ID Application **certificate + private key** and the **notarytool API key** are referenced through the macOS Keychain only — never read from the repo, never echoed.
- `.gitignore` extended with `*.key`/`*.pem`/`*.p8`/`*.p12`/`*.cer` as a defensive guard against any on-disk signing material.

### Entitlements / Hardened Runtime

- `LinkHub/LinkHub.entitlements` contains exactly one key: `com.apple.security.personal-information.location` (`true`). The verify step echoes the embedded entitlements so the operator can confirm Location-only (NFR17).
- Hardened Runtime is set in the Release build config (`project.yml`, owned by Stories 4.1–4.3) — `notarize.sh` does not set it; it only verifies the result. A failed notarization with Hardened Runtime off is surfaced by the notary log fetch.

### Scope boundaries

- This story authored `ExportOptions.plist` + `scripts/notarize.sh` only. It did **not** touch `Info.plist`, `project.yml`, or any `LinkHub/` Swift source (Stories 4.1–4.3 own Sparkle wiring + Info.plist keys).
- DMG packaging is Story 4.5; appcast signing is Story 4.6. `notarize.sh` ends by pointing at `make-dmg.sh`.

### File-structure (this story creates / modifies)

| File | Status | Purpose |
|---|---|---|
| `ExportOptions.plist` | NEW | Developer ID export options (placeholder Team ID) |
| `scripts/notarize.sh` | NEW (exec) | archive → export → notarize → staple → verify |
| `.gitignore` | MODIFIED | add `*.key`/`*.pem`/`*.p8`/`*.p12`/`*.cer` |
