# Story 4.5: DMG Packaging Script

Status: done

## Story

As a user,
I want to download a DMG with a single drag-to-Applications affordance,
so that installing LinkHub feels like installing any other Mac app.

## Acceptance Criteria

1. **DMG with app + /Applications symlink**
   - **Given** a stapled `LinkHub.app`
   - **When** `scripts/make-dmg.sh` runs
   - **Then** the output is `LinkHub-{version}.dmg` containing `LinkHub.app` and an `/Applications` symlink (FR51)
   - **And** the DMG is plain (no custom background image)

2. **Signature + staple survive packaging**
   - **Given** the DMG
   - **When** `codesign --verify --deep --strict` runs against the contained app
   - **Then** the signature and stapled notarization ticket are intact

3. **Drag-install with no Gatekeeper warning**
   - **Given** the user double-clicks the DMG
   - **When** the volume mounts
   - **Then** the user can drag `LinkHub.app` onto the `/Applications` symlink and run it without Gatekeeper warnings (FR52)

## Tasks / Subtasks

- [x] **Task 1: `scripts/make-dmg.sh` — package + verify** (AC: #1, #2)
  - [x] `#!/usr/bin/env bash`, `set -euo pipefail`, executable (`chmod +x`)
  - [x] Inputs: `$1`/`LINKHUB_APP_PATH` (default `build/export/LinkHub.app`), `$2`/`LINKHUB_VERSION` (REQUIRED), `LINKHUB_BUILD_DIR` (default `build`)
  - [x] Preflight: requires `hdiutil`, a version string, the app dir, and that the input app is already stapled (`xcrun stapler validate`) — refuses to package an unstapled app (would fail offline Gatekeeper)
  - [x] Stage `LinkHub.app` + `ln -s /Applications` symlink into a temp folder
  - [x] `hdiutil create -srcfolder <staging> -volname LinkHub -fs HFS+ -format UDRW` → writable image (auto-sized via `-srcfolder`, no fixed `-size`)
  - [x] `hdiutil convert -format UDZO -imagekey zlib-level=9` → compressed read-only `build/LinkHub-<version>.dmg`
  - [x] Plain DMG — no custom background image (docs/09 decision #12)
  - [x] `trap` cleanup detaches the volume and removes temp artifacts even on failure
  - [x] Post-build verify: mount the produced DMG read-only, assert `LinkHub.app` + `Applications` symlink present, run `codesign --verify --deep --strict --verbose=2` and `xcrun stapler validate` against the contained app, then detach
  - [x] Print byte size + next steps (staple the DMG, then `update-appcast.sh`)
- [ ] **Task 2: Local execution (maintainer gate — NOT runnable here)**
  - [ ] Run on macOS against a stapled `LinkHub.app` from Story 4.4; double-click the DMG, drag to `/Applications`, confirm launch with no Gatekeeper warning
  - **GATE:** requires macOS (`hdiutil`, `codesign`, `xcrun stapler`) and a stapled, notarized `LinkHub.app` from `notarize.sh`. Cannot run on Linux/web.

## Dev Notes

### Tool / command choices (and why)

| Concern | Choice | Rationale (docs/09) |
|---|---|---|
| Artifact format | `.app` in `.dmg` with `/Applications` symlink | Decision #10 — standard macOS install UX (Bartender, Amphetamine); `.dmg` is the notarized/stapled container |
| DMG appearance | Plain, no background | Decision #12 — avoids a design asset to maintain across dark/light/macOS changes |
| Image build | `hdiutil create -srcfolder ... -format UDRW` then `hdiutil convert -format UDZO` | docs/09 DMG Creation; `-srcfolder` auto-sizes (simpler than fixed `-size 60m` + mount + copy) and yields a clean compressed read-only DMG |
| Compression | `UDZO` (zlib, `zlib-level=9`) | Standard read-only compressed format Finder mounts directly |

### Staple-of-the-DMG is intentionally a separate step

The DMG itself must **also** be stapled before publishing (Gatekeeper checks the outermost container first — docs/09 Constraints). `make-dmg.sh` deliberately does **not** notarize/staple the DMG: that requires a notary round-trip identical to `notarize.sh`. Keeping packaging and notarization separable matches the docs/09 Release Checklist, which stales the DMG as its own checklist line. The script footer reminds the operator: `xcrun stapler staple build/LinkHub-<version>.dmg`.

### Verification rationale

Re-verifying signature + staple on the app *inside the mounted DMG* (AC #2) proves the `cp -R` into the image preserved the code signature and the embedded ticket. The mount is read-only and `-nobrowse` so it does not surface in Finder during the build.

### Scope boundaries

- This story authored `scripts/make-dmg.sh` only. No `Info.plist`/`project.yml`/Swift source touched.
- Versioning rule (SemVer short string / monotonic integer build) is documented in Story 4.6; here the version string is just the filename token and must match `CFBundleShortVersionString`.

### File-structure (this story creates)

| File | Status | Purpose |
|---|---|---|
| `scripts/make-dmg.sh` | NEW (exec) | stapled app → plain compressed DMG + /Applications symlink, with post-build verify |
