#!/usr/bin/env bash
#
# make-dmg.sh — Package a stapled LinkHub.app into a plain, compressed DMG
#               with a drag-to-/Applications affordance (Story 4.5).
#
# Output: LinkHub-<version>.dmg containing:
#   - LinkHub.app          (the stapled, notarized app from notarize.sh)
#   - Applications         (symlink to /Applications for drag-install)
#
# The DMG is plain (no custom background image) per docs/09 decision #12.
# After creation, the contained app's signature and notarization staple are
# re-verified to prove they survived the copy.
#
# ---------------------------------------------------------------------------
# REQUIRED LOCAL ENVIRONMENT:
#   - macOS (provides hdiutil, codesign, xcrun stapler).
#   - A stapled, notarized LinkHub.app (produce it with scripts/notarize.sh).
#
# ARGUMENTS / ENV:
#   $1  or  LINKHUB_APP_PATH   Path to the stapled LinkHub.app.
#                              Default: build/export/LinkHub.app
#   $2  or  LINKHUB_VERSION    Version string for the filename, e.g. 1.0.0
#                              (matches CFBundleShortVersionString). REQUIRED.
#   LINKHUB_BUILD_DIR          Output dir. Default: build.
#
# USAGE:
#   scripts/make-dmg.sh build/export/LinkHub.app 1.0.0
#   LINKHUB_VERSION=1.0.0 scripts/make-dmg.sh           # uses default app path
#
# NOTE: The DMG itself should ALSO be stapled before publishing — Gatekeeper
#       checks the outermost container first. Staple it after this script:
#         xcrun stapler staple build/LinkHub-1.0.0.dmg
#       (Stapling the DMG requires the DMG to have been notarized; submit it
#        to notarytool the same way notarize.sh submits the .zip, or notarize
#        the DMG directly. Kept out of this script to keep packaging and
#        notarization steps separable — see docs/09 Release Checklist.)
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="${LINKHUB_BUILD_DIR:-build}"
APP_PATH="${1:-${LINKHUB_APP_PATH:-$BUILD_DIR/export/LinkHub.app}}"
VERSION="${2:-${LINKHUB_VERSION:-}}"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  OK\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preflight ------------------------------------------------------------
log "Preflight checks"
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found — macOS required."
[ -n "$VERSION" ] || die "Version is required (arg \$2 or LINKHUB_VERSION), e.g. 1.0.0."
[ -d "$APP_PATH" ] || die "App not found at: $APP_PATH"

# Refuse to package an app that is not stapled — a DMG of an unstapled app
# would fail offline Gatekeeper (critical for a network tool — see docs/09).
xcrun stapler validate "$APP_PATH" \
    || die "Input app is NOT stapled. Run scripts/notarize.sh first."
ok "Input app is stapled and present: $APP_PATH"

mkdir -p "$BUILD_DIR"
DMG_FINAL="$BUILD_DIR/LinkHub-$VERSION.dmg"
DMG_RW="$(mktemp -t LinkHub_rw).dmg"
STAGING="$(mktemp -d -t LinkHub_dmg_staging)"
cleanup() {
    # Detach the volume if still mounted, then remove temp artifacts.
    [ -n "${MOUNT_DIR:-}" ] && hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    rm -rf "$DMG_RW" "$STAGING"
}
trap cleanup EXIT

rm -f "$DMG_FINAL"

# --- Stage contents -------------------------------------------------------
log "Staging DMG contents"
cp -R "$APP_PATH" "$STAGING/LinkHub.app"
ln -s /Applications "$STAGING/Applications"
ok "Staged LinkHub.app + /Applications symlink."

# --- Build read-write image from the staging folder ----------------------
# -srcfolder sizes the image automatically; UDRW is writable so we can tweak,
# then convert to compressed read-only below.
log "Creating writable disk image"
hdiutil create \
    -srcfolder "$STAGING" \
    -volname "LinkHub" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$DMG_RW" >/dev/null
ok "Writable image: $DMG_RW"

# --- Convert to compressed read-only DMG (UDZO = zlib) --------------------
log "Converting to compressed read-only DMG"
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_FINAL" >/dev/null
[ -f "$DMG_FINAL" ] || die "DMG not produced at $DMG_FINAL."
ok "DMG: $DMG_FINAL"

# --- Verify the contained app survived the copy ---------------------------
log "Verifying signature + staple inside the produced DMG"
MOUNT_DIR="$(mktemp -d -t LinkHub_verify_mount)"
hdiutil attach "$DMG_FINAL" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null

VERIFY_APP="$MOUNT_DIR/LinkHub.app"
[ -d "$VERIFY_APP" ]              || die "LinkHub.app missing inside the DMG."
[ -L "$MOUNT_DIR/Applications" ]  || die "/Applications symlink missing inside the DMG."

codesign --verify --deep --strict --verbose=2 "$VERIFY_APP" \
    || die "Signature invalid on the app inside the DMG."
ok "codesign --verify passed inside DMG."

xcrun stapler validate "$VERIFY_APP" \
    || die "Staple missing on the app inside the DMG."
ok "stapler validate passed inside DMG."

hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNT_DIR=""   # detached; don't re-detach in cleanup

BYTES="$(stat -f%z "$DMG_FINAL" 2>/dev/null || wc -c < "$DMG_FINAL")"
log "DONE — $DMG_FINAL ($BYTES bytes)"
printf 'Next:\n'
printf '  1. (Notarize +) staple the DMG:  xcrun stapler staple "%s"\n' "$DMG_FINAL"
printf '  2. Sign for Sparkle + update appcast:  scripts/update-appcast.sh "%s" %s\n' "$DMG_FINAL" "$VERSION"
