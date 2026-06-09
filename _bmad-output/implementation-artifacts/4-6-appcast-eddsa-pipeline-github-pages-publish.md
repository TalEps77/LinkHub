# Story 4.6: Appcast EdDSA Pipeline + GitHub Pages Publish

Status: done

## Story

As a user,
I want updates served from a stable, public appcast feed signed with a key only the maintainer holds,
so that update authenticity is verifiable end-to-end.

## Acceptance Criteria

1. **EdDSA signature from the Keychain + item appended**
   - **Given** a new release DMG
   - **When** `scripts/update-appcast.sh` runs
   - **Then** the script computes the EdDSA signature using the private key stored in the macOS Keychain (NFR16)
   - **And** appends a new `<item>` to `appcast/appcast.xml` with version, release-notes link, enclosure URL, length, and `sparkle:edSignature`

2. **GitHub Pages serves the feed**
   - **Given** `appcast/appcast.xml`
   - **When** committed and pushed
   - **Then** GitHub Pages publishes it at `https://talepstein.github.io/LinkHub/appcast.xml`

3. **Versioning rule**
   - **Given** versioning
   - **When** the release is tagged
   - **Then** `CFBundleShortVersionString` is `MAJOR.MINOR.PATCH` (SemVer) and `CFBundleVersion` is a monotonic integer

4. **Signature verification end-to-end**
   - **Given** the published feed
   - **When** Sparkle on a running LinkHub fetches it
   - **Then** EdDSA signature verification against `SUPublicEDKey` from `Info.plist` succeeds (NFR16)
   - **And** signature mismatch causes Sparkle to reject the update

## Tasks / Subtasks

- [x] **Task 1: `appcast/appcast.xml` — valid RSS+Sparkle skeleton** (AC: #2, #4)
  - [x] RSS 2.0 with `xmlns:sparkle` (`http://www.andymatuschak.org/xml-namespaces/sparkle`) + `xmlns:dc` namespaces
  - [x] `<channel>` metadata: `title`, `link` (the Pages URL), `description`, `language`
  - [x] No live items — a commented placeholder `<item>` (clearly marked "not a real release") documents the shape; `update-appcast.sh` inserts the first real item above the channel's anchor line
  - [x] Header comment documents the stable-URL invariant, the Keychain-only private key, the SUPublicEDKey verify behavior, and the versioning rule
- [x] **Task 2: `scripts/update-appcast.sh` — sign DMG + insert item** (AC: #1, #3)
  - [x] `#!/usr/bin/env bash`, `set -euo pipefail`, executable (`chmod +x`)
  - [x] Inputs: `$1`/`LINKHUB_DMG_PATH` (REQUIRED), `$2`/`LINKHUB_VERSION` (SemVer, REQUIRED), `$3`/`LINKHUB_BUILD` (monotonic integer, REQUIRED); overridable `LINKHUB_SIGN_UPDATE`/`MIN_OS`/`BASE_URL`/`APPCAST`
  - [x] Preflight validates inputs, incl. a SemVer shape check on the version and integer check on the build
  - [x] Locates Sparkle's `sign_update` via `LINKHUB_SIGN_UPDATE`, `$PATH`, SPM checkout paths, or Xcode DerivedData SPM artifacts
  - [x] Runs `sign_update <dmg>` — reads the Ed25519 **private key from the Keychain** (never disk/repo); parses `sparkle:edSignature` and `length` (falls back to file size if `length` is omitted)
  - [x] Builds an `<item>` with title, `sparkle:version` (= build), `sparkle:shortVersionString` (= version), `sparkle:minimumSystemVersion`, `sparkle:releaseNotesLink`, `pubDate`, and `<enclosure>` whose `url` is under `https://talepstein.github.io/LinkHub/`, with `sparkle:edSignature` + `length` + `type`
  - [x] Refuses to insert a duplicate `sparkle:version` (enforces the monotonic-integer rule); inserts the new item as the newest entry (after the `<language>` anchor) using a portable BSD/GNU-safe read loop (no GNU-only `sed -i`)
  - [x] Prints next steps (review diff + GitHub Pages publish)
- [ ] **Task 3: Local execution (maintainer gate — NOT runnable here)**
  - [ ] Run on macOS with the Sparkle EdDSA private key in the Keychain and `sign_update` available; confirm a valid `sparkle:edSignature` is inserted and Sparkle accepts the published feed
  - [ ] Publish `appcast/appcast.xml` to GitHub Pages; verify it is served at `https://talepstein.github.io/LinkHub/appcast.xml`
  - **GATE:** requires macOS + the Sparkle Ed25519 **private key** in the Keychain + Sparkle's `sign_update` tool (ships with the SPM Sparkle package resolved in Story 4.3), plus push access to the GitHub Pages branch. Cannot run on Linux/web.

## Dev Notes

### Tool choice: `sign_update` (not `generate_appcast`) — and why

docs/09 documents both. `generate_appcast` scans a directory of DMGs and regenerates the **entire** feed, inferring each item's version/length from the DMG's embedded `Info.plist`. LinkHub publishes one DMG per tagged release with a curated release-notes link and a stable GitHub-Pages enclosure URL. The surgical "sign one DMG, insert one item" path keeps `appcast/appcast.xml` a small, reviewable, hand-curatable diff per release and avoids re-deriving the whole feed (and re-fetching every prior DMG) each time. `update-appcast.sh` therefore drives `sign_update`. Both tools read the same Keychain private key; switching to `generate_appcast` later requires no Info.plist or key change.

Both `generate_keys` and `sign_update` are not on `$PATH` under SPM — the script searches the SPM checkout / DerivedData artifact locations documented in docs/09 § Accessing Sparkle Command-Line Tools, with `LINKHUB_SIGN_UPDATE` as an explicit override.

### Key handling (NFR16)

- The Ed25519 **private key lives only in the macOS Keychain** on the release machine (created once via Sparkle's `generate_keys`). `update-appcast.sh` never reads, writes, or echoes it — `sign_update` accesses the Keychain itself.
- The **public key** is in `Info.plist` as `SUPublicEDKey` (set by Story 4.3 — out of this story's scope). Sparkle verifies each enclosure's `sparkle:edSignature` against that public key; **a signature mismatch causes Sparkle to reject the update and refuse to install it** (AC #4). This is the end-to-end authenticity guarantee.
- `.gitignore` extended with `*.key`/`*.pem`/`*.p8`/`*.p12`/`*.cer` as a defensive guard.

### Versioning rule (AC #3) — documented and enforced

| Info.plist key | Appcast field | Format | Rule |
|---|---|---|---|
| `CFBundleShortVersionString` | `sparkle:shortVersionString` | `MAJOR.MINOR.PATCH` (SemVer) | Shown to users in the Sparkle dialog |
| `CFBundleVersion` | `sparkle:version` | monotonic integer | Sparkle/Gatekeeper compare numerically; must never decrease, never dotted |

`update-appcast.sh` validates the SemVer shape of `$VERSION` and the integer shape of `$BUILD`, and refuses to insert an item whose `sparkle:version` already exists — enforcing the monotonic-integer invariant at release time. Git tagging is `vMAJOR.MINOR.PATCH`; the DMG filename is `LinkHub-MAJOR.MINOR.PATCH.dmg` (docs/09 § Versioning Scheme).

### GitHub Pages publish step (AC #2)

1. Enable GitHub Pages for the `LinkHub` repo (e.g. Pages source = a `gh-pages` branch or `/docs` on the default branch), serving the repository at `https://talepstein.github.io/LinkHub/`.
2. Place the updated `appcast.xml` at the served root so it resolves to `https://talepstein.github.io/LinkHub/appcast.xml` (this URL is compiled into every binary as `SUFeedURL` and must never change after v1.0.0 — docs/09 Constraints).
3. Host the release DMG at the enclosure URL — either as a GitHub Release asset proxied to the Pages path, or copied alongside the appcast under the Pages root (the script's `BASE_URL` defaults to the Pages origin; override `LINKHUB_BASE_URL` if hosting DMGs elsewhere).
4. Commit + push `appcast/appcast.xml`; GitHub Pages publishes it automatically.

### Scope boundaries

- This story authored `appcast/appcast.xml` + `scripts/update-appcast.sh` only.
- **Did NOT touch `Info.plist`** — `SUFeedURL`/`SUPublicEDKey`/Sparkle wiring are Story 4.3 (parallel agent). Did not touch `project.yml` or any Swift source.

### File-structure (this story creates)

| File | Status | Purpose |
|---|---|---|
| `appcast/appcast.xml` | NEW | valid RSS+Sparkle skeleton served at the Pages URL |
| `scripts/update-appcast.sh` | NEW (exec) | `sign_update` the DMG (Keychain key) + insert a release `<item>` |
| `.gitignore` | MODIFIED (shared w/ 4.4) | add signing-material patterns |
