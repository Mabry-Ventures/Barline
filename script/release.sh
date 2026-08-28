#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_PATH="${DEVELOPER_DIR:-$(xcode-select -p)}"
SHA="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ROOT="$ROOT/.artifacts/release/$SHA"
ARCHIVE="$RELEASE_ROOT/Barline.xcarchive"

if [[ -n "$(git -C "$ROOT" status --porcelain=v1)" ]]; then
    printf 'error: release dry run requires a clean exact candidate\n' >&2
    exit 1
fi

for required in LICENSE NOTICE.md THIRD_PARTY_NOTICES.md PRIVACY.md SECURITY.md; do
    [[ -s "$ROOT/$required" ]] || {
        printf 'error: required distribution file is missing or empty: %s\n' "$required" >&2
        exit 1
    }
done

mkdir -p "$RELEASE_ROOT"
/bin/rm -rf "$ARCHIVE"
env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild \
    -project "$ROOT/Barline.xcodeproj" -scheme Barline -configuration Release \
    -destination 'generic/platform=macOS,arch=arm64' -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive

APP="$ARCHIVE/Products/Applications/Barline.app"
HELPER="$APP/Contents/XPCServices/BarlineMenuService.xpc"
INTENTS="$APP/Contents/PlugIns/BarlineIntents.appex"
for product in "$APP" "$HELPER" "$INTENTS"; do
    [[ -e "$product" ]] || {
        printf 'error: archive is missing embedded product: %s\n' "$product" >&2
        exit 1
    }
done

[[ "$(/usr/bin/lipo -archs "$APP/Contents/MacOS/Barline")" == arm64 ]] || {
    printf 'error: release application is not thin arm64\n' >&2
    exit 1
}
/usr/bin/plutil -lint "$APP/Contents/Info.plist" "$HELPER/Contents/Info.plist" "$INTENTS/Contents/Info.plist"
/usr/bin/grep -q 'group.com.mabryventures.Barline' "$ROOT/Barline/Barline.entitlements"
/usr/bin/grep -q 'group.com.mabryventures.Barline' "$ROOT/BarlineIntents/BarlineIntents.entitlements"

BOUNDARIES="$RELEASE_ROOT/distribution-boundaries.json"
SHA_VALUE="$SHA" ARCHIVE_VALUE="$ARCHIVE" /usr/bin/ruby -rjson -e '
  document = {
    commit_sha: ENV.fetch("SHA_VALUE"),
    unsigned_archive: ENV.fetch("ARCHIVE_VALUE"),
    archive_topology_validated: true,
    externally_blocked: [
      "Developer ID signing and nested entitlement verification",
      "Apple notarization and stapling",
      "Sparkle EdDSA key and production appcast publication",
      "GitHub repository administration and protected status configuration"
    ]
  }
  File.write(ARGV.fetch(0), JSON.pretty_generate(document) + "\n")
' "$BOUNDARIES"

printf 'PASS: unsigned exact-candidate archive topology and distribution contents validated\n'
printf 'BLOCKED EXTERNALLY: signing, notarization, Sparkle publication, and GitHub administration; see %s\n' "$BOUNDARIES"
