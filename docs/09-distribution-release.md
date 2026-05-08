# PRD 09 — Distribution & Release

**Status:** ✅ Done  
**Depends on:** 01, 08  
**Blocks:** —

---

## Problem Statement

> Which distribution channel should LinkHub use, what code-signing setup does that require,
> how is the binary notarized, what auto-update strategy fits a Developer ID app, and what
> form should the release artifact take?

This PRD decides:

- **Distribution channel** — Mac App Store vs. Developer ID direct distribution
- **Code signing** — certificate type, provisioning profile requirement
- **Notarization** — `notarytool` workflow, stapling for offline Gatekeeper
- **Auto-update strategy** — Sparkle 2 vs. manual update check vs. no updates
- **Release artifact** — `.dmg`, `.zip`, or `.pkg`
- **Versioning scheme** — `CFBundleShortVersionString` and `CFBundleVersion` conventions

---

## Decision Log

| # | Decision | Options Considered | Choice | Rationale |
|---|----------|--------------------|--------|-----------|
| 1 | **Distribution channel** | Mac App Store (MAS); Developer ID direct distribution | **Developer ID direct distribution** | MAS mandates App Sandbox. As established in PRD 08, App Sandbox blocks `CWWiFiClient.associate(to:password:rememberCredentials:)` — the core join-network feature — and complicates SCDynamicStore access. LinkHub's functionality is fundamentally incompatible with the sandbox entitlement model available on MAS. Developer ID allows full CoreWLAN access, Hardened Runtime without sandbox, and is the established channel for power-user macOS utilities (Little Snitch, Bartender, Amphetamine, Lulu). |
| 2 | **Certificate type** | Mac App Distribution; Developer ID Application; ad-hoc | **Developer ID Application** | `Mac App Distribution` certificates are only valid for MAS submissions — they produce binaries that Gatekeeper rejects outside the MAS sandbox. `Developer ID Application` is the correct certificate for notarized direct-distribution binaries. One certificate covers all release builds; no separate certificate per version is needed. |
| 3 | **Provisioning profile** | Required; not required | **No provisioning profile** | Developer ID apps do not use provisioning profiles. Code signing for Developer ID uses only the certificate, the entitlements file, and the team's signing identity. Provisioning profiles are a MAS and iOS concept. This simplifies the build pipeline significantly — no profile expiry, no device registration. |
| 4 | **Notarization tool** | Legacy `altool` (deprecated); `notarytool` (Xcode 13+) | **`xcrun notarytool submit`** | `altool` notarization was deprecated at WWDC 2022 and removed in Xcode 14. `notarytool` is faster (minutes vs. hours), supports App Store Connect API keys for CI, and is the only supported path from Xcode 13+. |
| 5 | **Notarytool authentication** | Apple ID + app-specific password; App Store Connect API key | **App Store Connect API key** (`--key`, `--key-id`, `--issuer-id` flags) | Apple ID + app-specific password is deprecated for automation and will eventually be removed. API key authentication is non-interactive, CI-compatible, and avoids storing Apple ID credentials in the build environment. Store the key in a local keychain profile (`notarytool store-credentials`) for one-command submission. |
| 6 | **Stapling** | Skip stapling; staple after notarization | **Always staple — `xcrun stapler staple LinkHub.app`** | Stapling embeds the notarization ticket into the `.app` bundle, enabling Gatekeeper to validate the binary offline (no network call at launch). Without stapling, Gatekeeper makes an online OCSP/ticket request that fails if the user has no internet at first launch — unacceptable for a network-management tool that may be launched specifically when connectivity is broken. |
| 7 | **Auto-update strategy** | Sparkle 2 (SPM-compatible); manual update-check URL; no auto-update | **Sparkle 2 via Swift Package Manager** | No auto-update forces users to manually check for releases — unacceptable for a persistent menu bar utility where security fixes and compatibility updates are invisible to users. A manual URL check adds complexity without the UI polish of Sparkle. Sparkle 2 is SPM-native (no CocoaPods/Carthage), widely deployed (used by BBEdit, Transmit, many macOS utilities), uses EdDSA (Ed25519) signatures for secure update delivery, and provides a built-in update UI. Its SPM package URL is `https://github.com/sparkle-project/Sparkle`. |
| 8 | **Sparkle signature algorithm** | RSA/DSA (deprecated in Sparkle 2); EdDSA (Ed25519) | **EdDSA (Ed25519)** | Sparkle 2 dropped DSA/RSA support entirely. `generate_keys` from the Sparkle tools directory generates the Ed25519 key pair. The private key is stored in the macOS Keychain (never in the repo); the public key goes in `Info.plist` as `SUPublicEDKey`. |
| 9 | **Sparkle appcast hosting** | GitHub Releases raw URL; GitHub Pages; custom domain | **GitHub Pages (`appcast.xml` at a stable path)** | A raw GitHub Releases URL changes per release, requiring every shipped binary to point at a version-specific URL — impractical. GitHub Pages provides a stable URL (`talepstein.github.io/LinkHub/appcast.xml`) that is updated in place each release. Custom domain adds infrastructure overhead without benefit at this stage. |
| 10 | **Release artifact format** | `.app` in `.dmg`; `.app` in `.zip`; `.pkg` installer | **`.app` inside a `.dmg` with an `/Applications` symlink** | `.dmg` with drag-to-Applications is the macOS standard UX for user-installed apps and what users of utilities like Alfred, Bartender, and Amphetamine expect. `.zip` is simpler to produce but lacks the install affordance and Finder handles quarantine attributes less predictably. `.pkg` adds complexity suited to apps requiring root-level installs, helper daemons, or kernel extensions — none of which LinkHub needs. The `.dmg` is the artifact that gets notarized and stapled. |
| 11 | **Versioning scheme** | Semantic versioning (MAJOR.MINOR.PATCH); CalVer; simple increment | **Semantic versioning — `CFBundleShortVersionString` = `MAJOR.MINOR.PATCH`, `CFBundleVersion` = monotonically increasing integer** | SemVer communicates change magnitude to users (1.0.0 → 1.0.1 is a patch; 1.0.0 → 1.1.0 adds features). `CFBundleVersion` must be a monotonically increasing integer for Gatekeeper and Sparkle to correctly determine which version is newer — it must never decrease across releases. |
| 12 | **DMG background and appearance** | Plain (no background); custom background image; dark/light adaptive | **Plain, no custom background image** | Custom background images require a design asset to maintain across macOS version changes that affect dark/light mode. A clean minimal DMG is indistinguishable from commercial apps (VS Code, Figma use plain DMGs). Saves time and avoids future maintenance. |

---

## Code Signing Setup (normative)

### Certificate

| Item | Value |
|------|-------|
| Certificate type | `Developer ID Application: <Team Name> (<TEAMID>)` |
| Issued by | Apple Worldwide Developer Relations CA |
| Validity | 5 years from issuance |
| Stored in | macOS login keychain on the build machine |
| Xcode setting | `CODE_SIGN_IDENTITY = Developer ID Application` (Release config) |
| Xcode setting | `DEVELOPMENT_TEAM = <TEAMID>` |

### Entitlements

From PRD 08 — `LinkHub/LinkHub.entitlements` contains exactly one key:

```xml
<key>com.apple.security.personal-information.location</key>
<true/>
```

### Build command (Release archive)

```bash
xcodebuild archive \
  -project LinkHub.xcodeproj \
  -scheme LinkHub \
  -configuration Release \
  -archivePath build/LinkHub.xcarchive

xcodebuild -exportArchive \
  -archivePath build/LinkHub.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

**`ExportOptions.plist`** (checked into repo root; substitute `<TEAMID>` before use):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string><TEAMID></string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

---

## Notarization Workflow (normative)

### One-time setup

```bash
xcrun notarytool store-credentials "linkhub-notary" \
  --key ~/private_keys/AuthKey_<KEYID>.p8 \
  --key-id <KEYID> \
  --issuer <ISSUER_UUID>
```

Stores the API key reference in the macOS Keychain under the profile name `"linkhub-notary"`. All subsequent `notarytool` commands reference this profile — no credentials in environment variables or shell history.

### Per-release steps

```bash
# 1. Zip the .app for submission (notarytool accepts .zip, .dmg, or .pkg)
ditto -c -k --keepParent build/export/LinkHub.app build/LinkHub.zip

# 2. Submit for notarization (--wait blocks until Apple responds, typically 1-3 min)
xcrun notarytool submit build/LinkHub.zip \
  --keychain-profile "linkhub-notary" \
  --wait

# 3. On status "Accepted" — staple the ticket to the .app
xcrun stapler staple build/export/LinkHub.app

# 4. Verify staple (must print "The validate action worked!")
xcrun stapler validate build/export/LinkHub.app

# 5. Create DMG from the stapled .app (see DMG Creation section)

# 6. Staple the DMG — Gatekeeper checks the outermost container first
xcrun stapler staple build/LinkHub-x.y.z.dmg
```

### Failure handling

If `notarytool submit` returns status `Invalid`, retrieve the full log:

```bash
xcrun notarytool log <submission-id> \
  --keychain-profile "linkhub-notary" \
  notarization-log.json
```

Common rejection reasons: `ENABLE_HARDENED_RUNTIME = YES` not set in the archive build, unsigned dynamic libraries bundled inside the `.app`, or entitlements file absent from the code-signed binary.

---

## Sparkle 2 Integration (normative)

### SPM dependency

Add to the Xcode project via **File → Add Package Dependencies**:

```
https://github.com/sparkle-project/Sparkle
```

Pin to the latest `2.x` release tag. Link the `Sparkle` library to the app target only (not test target).

### Accessing Sparkle Command-Line Tools (SPM)

When Sparkle is integrated via SPM, the `generate_keys` and `sign_update` binaries are not on `$PATH`. Two options:

**Option A — Use the SPM build checkout (recommended for CI):**

```bash
# After `xcodebuild` resolves packages, tools are at:
.build/checkouts/Sparkle/bin/generate_keys
.build/checkouts/Sparkle/bin/sign_update

# Run via swift:
$(xcrun --find swift) .build/checkouts/Sparkle/bin/generate_keys
```

**Option B — Download the release archive (recommended for local setup):**

1. Download `Sparkle-{version}.tar.xz` from the [Sparkle GitHub releases](https://github.com/sparkle-project/Sparkle/releases).
2. Extract — `generate_keys` and `sign_update` are in the `bin/` folder.
3. Run `./bin/generate_keys` once to generate your EdDSA key pair.

Store the private key in your keychain (the tool does this automatically). The public key goes in `Info.plist` as `SUPublicEDKey`.

### EdDSA key generation (one-time)

```bash
# Run from the Sparkle repo's bin/ directory after checking out the package
./bin/generate_keys
```

Output: private key stored in macOS Keychain under `"ed25519 key for <BundleID>"`; public key printed to stdout as a base64 string.

**Private key backup:** Export from Keychain and store in an encrypted vault. If the private key is lost, all previously installed copies of the app cannot receive future updates — the public key in `Info.plist` must match the signing key.

### Info.plist additions

```xml
<!-- Sparkle: public EdDSA key for update signature verification.
     Generated once via ./bin/generate_keys; paste the base64 output here. -->
<key>SUPublicEDKey</key>
<string>PASTE_PUBLIC_KEY_HERE</string>

<!-- Sparkle: stable appcast URL on GitHub Pages.
     Must not change after the first public release. -->
<key>SUFeedURL</key>
<string>https://talepstein.github.io/LinkHub/appcast.xml</string>

<!-- Sparkle: enable silent background update checks (user can disable in prefs) -->
<key>SUEnableAutomaticChecks</key>
<true/>
```

### AppDelegate wiring (minimal)

```swift
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Retain for app lifetime — SPUStandardUpdaterController starts the updater on init.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    // Expose for a "Check for Updates…" menu item action
    @IBAction func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }
}
```

> **Note — programmatic menu wiring (no `.xib` / `.storyboard`):** LinkHub builds its menu bar UI in code, so the "Check for Updates…" `NSMenuItem` cannot be wired to `checkForUpdates(_:)` via Interface Builder. Wire it explicitly wherever the app menu is constructed:
>
> ```swift
> // In AppDelegate.applicationDidFinishLaunching or wherever the app menu is built:
> if let checkItem = NSApp.mainMenu?
>     .item(withTitle: "LinkHub")?
>     .submenu?
>     .item(withTitle: "Check for Updates…") {
>     checkItem.target = self
>     checkItem.action = #selector(checkForUpdates(_:))
> }
> ```

No further code is needed for automatic background checks. Sparkle presents its own update UI when a new version is found.

### Appcast XML format

Canonical `appcast.xml` — updated in place on GitHub Pages for each release:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>LinkHub</title>
    <link>https://talepstein.github.io/LinkHub/appcast.xml</link>
    <description>LinkHub release feed</description>
    <language>en</language>
    <item>
      <title>Version 1.0.0</title>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <pubDate>Mon, 14 Apr 2026 00:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/TalEps77/LinkHub/releases/download/v1.0.0/LinkHub-1.0.0.dmg"
        sparkle:edSignature="BASE64_EDSIG_FROM_SIGN_UPDATE"
        length="BYTE_SIZE_OF_DMG"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

**Sign each release DMG before publishing the appcast:**

```bash
./bin/sign_update LinkHub-1.0.0.dmg
# Prints: sparkle:edSignature="..." — paste into appcast.xml enclosure attribute
```

---

## DMG Creation (normative)

```bash
# 1. Create a writable HFS+ image large enough for the .app
hdiutil create -size 60m -fs HFS+ -volname "LinkHub" /tmp/LinkHub_rw.dmg

# 2. Mount it
hdiutil attach /tmp/LinkHub_rw.dmg -mountpoint /Volumes/LinkHub

# 3. Copy the stapled .app and add an /Applications symlink
cp -R build/export/LinkHub.app /Volumes/LinkHub/
ln -s /Applications /Volumes/LinkHub/Applications

# 4. Unmount
hdiutil detach /Volumes/LinkHub

# 5. Convert to compressed read-only DMG (UDZO = zlib compression)
hdiutil convert /tmp/LinkHub_rw.dmg \
  -format UDZO \
  -o build/LinkHub-1.0.0.dmg

# 6. Staple the DMG (see Notarization Workflow above)
xcrun stapler staple build/LinkHub-1.0.0.dmg
```

---

## Versioning Scheme (normative)

| Info.plist key | Format | Example | Rules |
|----------------|--------|---------|-------|
| `CFBundleShortVersionString` | `MAJOR.MINOR.PATCH` | `1.0.0` | Shown to users in Sparkle update dialog and About window. Increment MINOR for new features, PATCH for bug fixes, MAJOR for breaking changes. |
| `CFBundleVersion` | Integer, monotonically increasing | `1` → `2` → `3` | Must never decrease across releases. Used by Gatekeeper and Sparkle for version comparison. Do **not** use a dotted string in this field. |

**Git tagging:** each release commit is tagged `vMAJOR.MINOR.PATCH` (e.g., `v1.0.0`). The GitHub Release title matches the tag. The DMG filename follows `LinkHub-MAJOR.MINOR.PATCH.dmg`.

---

## Release Checklist

Before each public release:

- [ ] Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`
- [ ] Build Release archive: `xcodebuild archive …`
- [ ] Export with `developer-id` method: `xcodebuild -exportArchive …`
- [ ] Submit `.app` (zipped) to `notarytool --wait`; confirm status `Accepted`
- [ ] Staple `.app`: `xcrun stapler staple …`; verify with `xcrun stapler validate …`
- [ ] Create `.dmg` from the stapled `.app` (see DMG Creation section)
- [ ] Staple `.dmg`: `xcrun stapler staple …`
- [ ] Sign `.dmg` with `./bin/sign_update`; paste `edSignature` into `appcast.xml`
- [ ] Tag git commit: `git tag vX.Y.Z`
- [ ] Create GitHub Release; attach `LinkHub-X.Y.Z.dmg` as a release asset
- [ ] Publish updated `appcast.xml` to GitHub Pages branch

---

## Constraints

- **Sandbox incompatibility is permanent:** `CWWiFiClient` network-join will not gain sandbox support retroactively — Apple treats low-level Wi-Fi control as incompatible with the MAS sandbox model. Reconsider MAS only if Apple ships a new sandboxable network-join API.
- **Notarization requires Xcode 13+ on macOS 10.15.6+:** `notarytool` ships with Xcode 13+. Builds on older environments cannot be notarized.
- **Sparkle 2 requires SPM and Xcode 12+:** Guaranteed by the project's Xcode 16 baseline (PRD 01).
- **EdDSA private key must never be committed to the repository:** The Sparkle private key lives in the macOS Keychain on the release machine only. Back it up to an encrypted vault before the first release.
- **`SUFeedURL` is permanent once shipped:** The appcast URL is compiled into every distributed binary. Changing it requires a migration release that redirects to the new URL. Choose the final GitHub Pages URL before cutting v1.0.0.
- **`CFBundleVersion` must be a monotonically increasing integer:** Sparkle and Gatekeeper compare this value numerically. A dotted string (e.g., `1.0.1`) in `CFBundleVersion` causes version comparison failures; dotted strings belong in `CFBundleShortVersionString` only.
- **Both the `.app` and the `.dmg` must be stapled:** Gatekeeper checks the outermost container first. An unstapled `.dmg` triggers an online ticket lookup even if the inner `.app` is stapled. This is critical for LinkHub, which may be opened when network connectivity is absent.

---

## Out of Scope

- **Mac App Store submission** — ruled out by the distribution channel decision; MAS entitlement requirements are not applicable.
- **iOS / iPadOS distribution** — LinkHub is macOS-only (PRD 01).
- **TestFlight** — not available for Developer ID apps; beta distribution is handled by sharing the notarized `.dmg` directly with testers.
- **Xcode Cloud / CI pipeline** — deferred; the manual workflow above is sufficient for solo/small-team development. Xcode Cloud can replace the manual steps later without changing any PRD decisions here.
- **`.pkg` installer** — ruled out; `.pkg` adds complexity appropriate only for apps installing system-level components (daemons, kernel extensions).
- **Sparkle delta updates** — Sparkle supports binary-diff delta updates for faster downloads; omitted here to keep the release pipeline simple. Revisit after the first stable release if download size becomes a concern.
- **Crash reporting** — no third-party crash reporter is added; `os.log` (PRD 01) and crash reports shared by users suffice at this stage.

---

## Open Questions

| # | Question | Status | Resolution |
|---|----------|--------|------------|
| 1 | Should the appcast be hosted on GitHub Pages (`talepstein.github.io/LinkHub/appcast.xml`) or via a custom domain? A custom domain decouples the feed URL from GitHub account ownership if the repo ever moves. | **Resolved** | Use `https://talepstein.github.io/LinkHub/appcast.xml`. No custom domain at initial release. `SUFeedURL` in `Info.plist` is set to this URL. |
| 2 | Should Sparkle's automatic update check run silently on first launch, or should it present an opt-in prompt ("Check for updates automatically?")? Sparkle 2's default behaviour is to show an opt-in dialog on first check. | **Resolved** | Sparkle 2 DOES show an opt-in permission dialog on first launch regardless of `SUEnableAutomaticChecks`. This is correct behaviour. LinkHub accepts this dialog — it gives users explicit control and is required for good UX on macOS. No workaround needed. |

---

## References

- [Apple Developer: Distributing your app outside the Mac App Store](https://developer.apple.com/documentation/xcode/distributing-your-app-outside-the-mac-app-store) — Developer ID code signing workflow.
- [Apple Developer: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — End-to-end notarization guide.
- [Apple Developer: Staple the ticket to your distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution#Staple-the-ticket-to-your-distribution) — `xcrun stapler staple`; why both `.app` and `.dmg` need stapling.
- [Apple Developer: Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime) — Required for notarization; independent of App Sandbox.
- [Apple Tech Note TN3135: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3135-inside-code-signing-provisioning-profiles) — Why Developer ID apps require no provisioning profile.
- [Sparkle Project: Getting Started](https://sparkle-project.org/documentation/) — SPM integration, `generate_keys`, `SUPublicEDKey`, `SUFeedURL`.
- [Sparkle Project: Publishing an Update](https://sparkle-project.org/documentation/publishing/) — `sign_update`, appcast XML schema, `sparkle:edSignature`.
- [Sparkle Project: GitHub repository](https://github.com/sparkle-project/Sparkle) — SPM package URL, `2.x` release tags, `SPUStandardUpdaterController` API.
- [WWDC 2022: What's new in notarization for Mac software (session 10109)](https://developer.apple.com/videos/play/wwdc2022/10109/) — `notarytool` migration from `altool`; App Store Connect API key authentication.
- [Apple HIG: Updating your app](https://developer.apple.com/design/human-interface-guidelines/updating-apps) — Update notification UX guidance.
