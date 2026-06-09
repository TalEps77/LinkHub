#!/usr/bin/env bash
#
# update-appcast.sh — Sign a release DMG with Sparkle's EdDSA key and insert
#                     an <item> into appcast/appcast.xml (Story 4.6).
#
# Pipeline:
#   1. Locate Sparkle's sign_update tool (SPM checkout or downloaded release).
#   2. sign_update <dmg>  -> reads the Ed25519 PRIVATE key from the macOS
#      Keychain, prints sparkle:edSignature="..." and length="...".
#      The private key is NEVER written to disk or read from the repo.
#   3. Build a fully-formed <item> (version, shortVersionString, release-notes
#      link, enclosure URL under https://talepstein.github.io/LinkHub/, length,
#      sparkle:edSignature) and insert it as the newest item in the channel.
#
# Sparkle verifies each update against SUPublicEDKey (Info.plist). If the
# signature does not match that public key, Sparkle REJECTS the update and
# refuses to install it — so the appcast MUST be signed with the matching key.
#
# WHY sign_update (not generate_appcast): generate_appcast scans a directory of
# DMGs and regenerates the whole feed, inferring version/length from each file's
# Info.plist. We publish one DMG per tagged release with curated release-notes
# links and a stable GitHub-Pages enclosure URL, so the surgical "sign one DMG,
# insert one item" path (sign_update) keeps the committed appcast.xml diffable
# and avoids re-deriving the entire feed each release. docs/09 documents both;
# this script follows the sign_update path.
#
# ---------------------------------------------------------------------------
# REQUIRED LOCAL ENVIRONMENT (cannot run on CI/web without these):
#   - macOS with the Sparkle EdDSA private key in the login Keychain
#     (created once via Sparkle's `generate_keys`; entry:
#      "Private key for signing your Sparkle updates").
#   - Sparkle's sign_update binary, located one of:
#       * LINKHUB_SIGN_UPDATE env var pointing at the binary, OR
#       * sign_update on $PATH, OR
#       * an SPM checkout under one of:
#           .build/checkouts/Sparkle/bin/sign_update
#           build/SourcePackages/checkouts/Sparkle/bin/sign_update
#           ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/
#                                              artifacts/sparkle/Sparkle/bin/sign_update
#     (After SPM resolves Sparkle in Story 4.3, the tool ships in the package.)
#
# ARGUMENTS / ENV:
#   $1 or LINKHUB_DMG_PATH    Path to the release DMG (LinkHub-<version>.dmg). REQUIRED.
#   $2 or LINKHUB_VERSION     SemVer short string, e.g. 1.0.0 (CFBundleShortVersionString). REQUIRED.
#   $3 or LINKHUB_BUILD       Monotonic integer build (CFBundleVersion). REQUIRED.
#   LINKHUB_SIGN_UPDATE       Explicit path to Sparkle's sign_update binary (optional).
#   LINKHUB_MIN_OS            sparkle:minimumSystemVersion. Default: 13.0.
#   LINKHUB_BASE_URL          Enclosure base URL. Default: https://talepstein.github.io/LinkHub
#   LINKHUB_APPCAST           Appcast path. Default: appcast/appcast.xml
#
# USAGE:
#   scripts/update-appcast.sh build/LinkHub-1.0.0.dmg 1.0.0 1
#
# After this script: commit appcast/appcast.xml and publish it to GitHub Pages
# so it is served at https://talepstein.github.io/LinkHub/appcast.xml
# (see this script's footer + docs/09 for the Pages publish step).
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DMG_PATH="${1:-${LINKHUB_DMG_PATH:-}}"
VERSION="${2:-${LINKHUB_VERSION:-}}"
BUILD="${3:-${LINKHUB_BUILD:-}}"
MIN_OS="${LINKHUB_MIN_OS:-13.0}"
BASE_URL="${LINKHUB_BASE_URL:-https://talepstein.github.io/LinkHub}"
APPCAST="${LINKHUB_APPCAST:-appcast/appcast.xml}"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  OK\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preflight ------------------------------------------------------------
log "Preflight checks"
[ -n "$DMG_PATH" ] || die "DMG path is required (arg \$1 or LINKHUB_DMG_PATH)."
[ -n "$VERSION" ]  || die "Version is required (arg \$2 or LINKHUB_VERSION), e.g. 1.0.0."
[ -n "$BUILD" ]    || die "Build is required (arg \$3 or LINKHUB_BUILD), a monotonic integer."
[ -f "$DMG_PATH" ] || die "DMG not found at: $DMG_PATH"
[ -f "$APPCAST" ]  || die "Appcast not found at: $APPCAST"
case "$VERSION" in
    *.*.*) : ;;  # crude SemVer shape check (MAJOR.MINOR.PATCH)
    *) die "Version '$VERSION' is not MAJOR.MINOR.PATCH (SemVer)." ;;
esac
case "$BUILD" in
    *[!0-9]*|'') die "Build '$BUILD' must be a non-negative integer (CFBundleVersion)." ;;
esac
ok "Inputs valid: DMG=$DMG_PATH version=$VERSION build=$BUILD"

# --- Locate Sparkle's sign_update -----------------------------------------
find_sign_update() {
    if [ -n "${LINKHUB_SIGN_UPDATE:-}" ] && [ -x "$LINKHUB_SIGN_UPDATE" ]; then
        printf '%s' "$LINKHUB_SIGN_UPDATE"; return 0
    fi
    if command -v sign_update >/dev/null 2>&1; then
        command -v sign_update; return 0
    fi
    local candidates=(
        ".build/checkouts/Sparkle/bin/sign_update"
        "build/SourcePackages/checkouts/Sparkle/bin/sign_update"
    )
    local c
    for c in "${candidates[@]}"; do
        [ -x "$c" ] && { printf '%s' "$c"; return 0; }
    done
    # Xcode DerivedData SPM artifacts (path contains a hash; glob it).
    local derived
    derived="$(ls -1 "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -n 1 || true)"
    [ -n "$derived" ] && [ -x "$derived" ] && { printf '%s' "$derived"; return 0; }
    return 1
}

log "Locating Sparkle sign_update tool"
SIGN_UPDATE="$(find_sign_update)" || die "sign_update not found. Set LINKHUB_SIGN_UPDATE,
     put it on PATH, or resolve the Sparkle SPM package (see header for paths)."
ok "sign_update: $SIGN_UPDATE"

# --- Sign the DMG (private key read from Keychain by sign_update) ---------
log "Signing $DMG_PATH with the Sparkle EdDSA private key (from Keychain)"
# sign_update prints, e.g.:  sparkle:edSignature="BASE64..." length="12345"
SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG_PATH")" \
    || die "sign_update failed. Is the Sparkle private key in the Keychain?"
printf '%s\n' "$SIGN_OUTPUT"

ED_SIG="$(printf '%s' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s' "$SIGN_OUTPUT"  | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[ -n "$ED_SIG" ] || die "Could not parse sparkle:edSignature from sign_update output."
# sign_update may omit length; fall back to the file size on disk.
if [ -z "$LENGTH" ]; then
    LENGTH="$(stat -f%z "$DMG_PATH" 2>/dev/null || wc -c < "$DMG_PATH" | tr -d ' ')"
fi
ok "EdDSA signature obtained; enclosure length=$LENGTH bytes."

# --- Build the <item> -----------------------------------------------------
DMG_FILE="$(basename "$DMG_PATH")"
ENCLOSURE_URL="$BASE_URL/$DMG_FILE"
NOTES_URL="$BASE_URL/release-notes/$VERSION.html"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

ITEM=$(cat <<EOF
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$NOTES_URL</sparkle:releaseNotesLink>
      <pubDate>$PUBDATE</pubDate>
      <enclosure
        url="$ENCLOSURE_URL"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream"/>
    </item>
EOF
)

# --- Insert the item as the newest entry in the channel -------------------
# Strategy: if an item for this exact build already exists, refuse (the operator
# must bump CFBundleVersion). Otherwise insert immediately after <language>...,
# so the newest release sits at the top of the channel.
if grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST"; then
    die "An item with sparkle:version $BUILD already exists in $APPCAST.
     CFBundleVersion must be a NEW monotonic integer per release. Bump it."
fi

log "Inserting <item> into $APPCAST"
TMP_ITEM="$(mktemp -t linkhub-appcast-item)"
trap 'rm -f "$TMP_ITEM"' EXIT
printf '%s\n' "$ITEM" > "$TMP_ITEM"

# Insert after the channel's <language> line (present in the skeleton). Using a
# temp file keeps the operation portable across BSD/GNU sed differences.
OUT="$(mktemp -t linkhub-appcast-out)"
INSERTED=0
while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" >> "$OUT"
    if [ "$INSERTED" -eq 0 ] && printf '%s' "$line" | grep -q "<language>"; then
        printf '\n' >> "$OUT"
        cat "$TMP_ITEM" >> "$OUT"
        INSERTED=1
    fi
done < "$APPCAST"

[ "$INSERTED" -eq 1 ] || die "Anchor <language> line not found in $APPCAST; cannot insert item."
mv "$OUT" "$APPCAST"
ok "Item for version $VERSION (build $BUILD) inserted."

log "DONE — $APPCAST updated."
printf 'Enclosure: %s\n' "$ENCLOSURE_URL"
printf 'Next steps:\n'
printf '  1. Review the diff:        git diff %s\n' "$APPCAST"
printf '  2. Publish to GitHub Pages so it is served at:\n'
printf '       %s/appcast.xml\n' "$BASE_URL"
printf '     (commit appcast/appcast.xml on the Pages-serving branch/dir, push;\n'
printf '      attach %s as the GitHub Release asset at the enclosure URL.)\n' "$DMG_FILE"
