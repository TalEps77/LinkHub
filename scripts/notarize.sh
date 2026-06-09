#!/usr/bin/env bash
#
# notarize.sh — Archive, export, notarize, and staple LinkHub.app for
#               Developer ID direct distribution (Story 4.4).
#
# Pipeline:
#   1. xcodebuild archive        -> build/LinkHub.xcarchive
#   2. xcodebuild -exportArchive -> build/export/LinkHub.app   (developer-id)
#   3. ditto -c -k               -> build/LinkHub.zip          (notarytool input)
#   4. xcrun notarytool submit   --keychain-profile linkhub-notary --wait
#   5. xcrun stapler staple      -> ticket embedded in LinkHub.app
#   6. verify: stapler validate, codesign --verify, spctl assess
#
# This produces a Gatekeeper-clean, Developer ID Application-signed app with
# Hardened Runtime enabled and the Location entitlement only (NFR13/15/17).
#
# ---------------------------------------------------------------------------
# REQUIRED LOCAL ENVIRONMENT (cannot run on CI/web without these):
#   - macOS + Xcode 16 (provides xcodebuild, xcrun, notarytool, stapler).
#   - A "Developer ID Application: <Team> (<TEAMID>)" certificate + private key
#     in the login keychain of THIS machine.
#   - A notarytool keychain profile named "linkhub-notary" created once via:
#
#       xcrun notarytool store-credentials "linkhub-notary" \
#         --key   ~/private_keys/AuthKey_<KEYID>.p8 \
#         --key-id <KEYID> \
#         --issuer <ISSUER_UUID>
#
#     (App Store Connect API key — non-interactive, CI-friendly. No Apple ID
#      password is stored anywhere. The profile lives in the macOS Keychain.)
#
# CONFIGURATION (env vars; override on the command line, never hardcode secrets):
#   LINKHUB_TEAM_ID         (REQUIRED) Apple Developer Team ID, e.g. ABCDE12345.
#                           Injected into a temp copy of ExportOptions.plist.
#   LINKHUB_NOTARY_PROFILE  notarytool keychain profile name. Default: linkhub-notary.
#   LINKHUB_SCHEME          xcodebuild scheme.            Default: LinkHub.
#   LINKHUB_CONFIGURATION   build configuration.          Default: Release.
#   LINKHUB_PROJECT         .xcodeproj path.              Default: LinkHub.xcodeproj.
#   LINKHUB_BUILD_DIR       output dir.                   Default: build.
#
# USAGE:
#   xcodegen generate                 # regenerate LinkHub.xcodeproj first
#   LINKHUB_TEAM_ID=ABCDE12345 scripts/notarize.sh
#
# On success the stapled, verified app is at: $BUILD_DIR/export/LinkHub.app
# Next: scripts/make-dmg.sh "$BUILD_DIR/export/LinkHub.app" <version>
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Resolve repo root so the script runs from anywhere -------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# --- Config ---------------------------------------------------------------
TEAM_ID="${LINKHUB_TEAM_ID:-}"
NOTARY_PROFILE="${LINKHUB_NOTARY_PROFILE:-linkhub-notary}"
SCHEME="${LINKHUB_SCHEME:-LinkHub}"
CONFIGURATION="${LINKHUB_CONFIGURATION:-Release}"
PROJECT="${LINKHUB_PROJECT:-LinkHub.xcodeproj}"
BUILD_DIR="${LINKHUB_BUILD_DIR:-build}"

ARCHIVE_PATH="$BUILD_DIR/LinkHub.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/LinkHub.app"
ZIP_PATH="$BUILD_DIR/LinkHub.zip"
EXPORT_OPTIONS_SRC="$REPO_ROOT/ExportOptions.plist"

# --- Helpers --------------------------------------------------------------
log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  OK\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preflight ------------------------------------------------------------
log "Preflight checks"
[ -n "$TEAM_ID" ] || die "LINKHUB_TEAM_ID is required (Apple Developer Team ID)."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found — Xcode required."
command -v xcrun      >/dev/null 2>&1 || die "xcrun not found — Xcode required."
[ -e "$PROJECT" ]            || die "$PROJECT not found. Run 'xcodegen generate' first."
[ -f "$EXPORT_OPTIONS_SRC" ] || die "ExportOptions.plist not found at repo root."
ok "Team ID, toolchain, project, and ExportOptions.plist present."

# Verify the notarytool keychain profile exists (history/log call is harmless).
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    die "notarytool keychain profile '$NOTARY_PROFILE' not found or invalid.
     Create it once with 'xcrun notarytool store-credentials' (see header)."
fi
ok "notarytool keychain profile '$NOTARY_PROFILE' reachable."

# --- Clean previous outputs ----------------------------------------------
log "Cleaning previous build outputs in $BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$ZIP_PATH"
mkdir -p "$BUILD_DIR"

# --- Inject Team ID into a temp ExportOptions.plist -----------------------
# The repo copy keeps a placeholder so no Team ID is committed.
EXPORT_OPTIONS="$(mktemp -t linkhub-exportoptions).plist"
trap 'rm -f "$EXPORT_OPTIONS"' EXIT
sed "s/__TEAMID__/$TEAM_ID/" "$EXPORT_OPTIONS_SRC" > "$EXPORT_OPTIONS"
ok "ExportOptions.plist prepared with Team ID."

# --- 1. Archive -----------------------------------------------------------
log "Archiving ($SCHEME / $CONFIGURATION)"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -quiet
[ -d "$ARCHIVE_PATH" ] || die "Archive not produced at $ARCHIVE_PATH."
ok "Archive: $ARCHIVE_PATH"

# --- 2. Export (Developer ID) --------------------------------------------
log "Exporting Developer ID app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"
[ -d "$APP_PATH" ] || die "Exported app not found at $APP_PATH."
ok "Exported: $APP_PATH"

# --- 3. Zip for notarytool ------------------------------------------------
log "Zipping app for notarization"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
ok "Zip: $ZIP_PATH"

# --- 4. Submit + wait -----------------------------------------------------
log "Submitting to Apple notary service (this blocks until a verdict, ~1-3 min)"
SUBMIT_OUTPUT="$(xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait 2>&1)" || { printf '%s\n' "$SUBMIT_OUTPUT"; die "notarytool submit failed."; }
printf '%s\n' "$SUBMIT_OUTPUT"

if ! printf '%s' "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    SUBMISSION_ID="$(printf '%s' "$SUBMIT_OUTPUT" | awk '/id:/ {print $2; exit}')"
    if [ -n "${SUBMISSION_ID:-}" ]; then
        printf '\nFetching notarization log for %s:\n' "$SUBMISSION_ID"
        xcrun notarytool log "$SUBMISSION_ID" \
            --keychain-profile "$NOTARY_PROFILE" || true
    fi
    die "Notarization was not Accepted. See log above (common causes: Hardened
     Runtime off, unsigned bundled dylibs, missing entitlements at sign time)."
fi
ok "Notarization Accepted."

# --- 5. Staple ------------------------------------------------------------
log "Stapling ticket to LinkHub.app"
xcrun stapler staple "$APP_PATH"
ok "Stapled."

# --- 6. Verify ------------------------------------------------------------
log "Verifying staple, signature, and Gatekeeper assessment"

xcrun stapler validate "$APP_PATH" \
    || die "stapler validate failed — ticket not embedded."
ok "stapler validate passed."

codesign --verify --deep --strict --verbose=2 "$APP_PATH" \
    || die "codesign --verify failed."
ok "codesign --verify passed (Developer ID Application)."

# Echo the entitlements + signing authority for the operator to eyeball:
# expect Hardened Runtime (runtime flag) and the Location entitlement ONLY.
log "Signing authority (expect 'Developer ID Application'):"
codesign --display --verbose=4 "$APP_PATH" 2>&1 | grep -i "Authority\|flags" || true

log "Entitlements (expect ONLY com.apple.security.personal-information.location):"
codesign --display --entitlements - --xml "$APP_PATH" 2>/dev/null \
    | plutil -convert xml1 -o - - 2>/dev/null || true

spctl --assess --type execute -vvv "$APP_PATH" \
    || die "spctl assessment failed — Gatekeeper would reject this app."
ok "spctl assessment passed — Gatekeeper-clean."

log "DONE — notarized & stapled app at: $APP_PATH"
printf 'Next: scripts/make-dmg.sh "%s" <version>\n' "$APP_PATH"
