#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_PATH="${DEVELOPER_DIR:-$(xcode-select -p)}"
SHA="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ROOT="$ROOT/.artifacts/release/$SHA"
ARCHIVE="$RELEASE_ROOT/Barline.xcarchive"
RELEASE_DERIVED_DATA="$RELEASE_ROOT/DerivedData"
UNSIGNED=false
NOTARY_PROFILE="${BARLINE_NOTARY_PROFILE:-}"
SPARKLE_ACCOUNT="${BARLINE_SPARKLE_ACCOUNT:-mabry-ventures-barline}"

usage() {
    printf 'usage: ./script/release.sh [--unsigned] [--notary-profile NAME] [--sparkle-account NAME]\n'
}

while (($#)); do
    case "$1" in
        --unsigned) UNSIGNED=true ;;
        --notary-profile)
            (($# >= 2)) || { usage >&2; exit 2; }
            NOTARY_PROFILE="$2"
            shift
            ;;
        --sparkle-account)
            (($# >= 2)) || { usage >&2; exit 2; }
            SPARKLE_ACCOUNT="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

validate_exact_candidate() {
    [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$SHA" ]] || {
        printf 'error: release HEAD changed from captured candidate %s\n' "$SHA" >&2
        exit 1
    }
    [[ -z "$(git -C "$ROOT" status --porcelain=v1)" ]] || {
        printf 'error: release requires a clean exact candidate\n' >&2
        exit 1
    }
}

validate_exact_candidate

for command in xcodebuild codesign ditto plutil ruby shasum; do
    command -v "$command" >/dev/null 2>&1 || { printf 'error: missing %s\n' "$command" >&2; exit 1; }
done
for required in LICENSE NOTICE.md THIRD_PARTY_NOTICES.md PRIVACY.md SECURITY.md docs/PROVENANCE.md docs/BUILDING.md; do
    [[ -s "$ROOT/$required" ]] || { printf 'error: required distribution file is missing or empty: %s\n' "$required" >&2; exit 1; }
done

mkdir -p "$RELEASE_ROOT"
/bin/rm -rf "$ARCHIVE" "$RELEASE_DERIVED_DATA"
archive_arguments=(
    -project "$ROOT/Barline.xcodeproj" -scheme Barline -configuration Release
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE"
    -derivedDataPath "$RELEASE_DERIVED_DATA"
    -clonedSourcePackagesDirPath "$RELEASE_DERIVED_DATA/SourcePackages" archive
)
if "$UNSIGNED"; then
    archive_arguments=(
        -project "$ROOT/Barline.xcodeproj" -scheme Barline -configuration Release
        -destination 'platform=macOS,arch=arm64' -archivePath "$ARCHIVE"
        -derivedDataPath "$RELEASE_DERIVED_DATA"
        -clonedSourcePackagesDirPath "$RELEASE_DERIVED_DATA/SourcePackages"
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
    )
fi
env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild "${archive_arguments[@]}"

APP="$ARCHIVE/Products/Applications/Barline.app"
HELPER="$APP/Contents/XPCServices/BarlineMenuService.xpc"
INTENTS="$APP/Contents/PlugIns/BarlineIntents.appex"
for product in "$APP" "$HELPER" "$INTENTS"; do
    [[ -e "$product" ]] || { printf 'error: archive is missing embedded product: %s\n' "$product" >&2; exit 1; }
done
[[ "$(/usr/bin/lipo -archs "$APP/Contents/MacOS/Barline")" == arm64 ]] || { printf 'error: release application is not thin arm64\n' >&2; exit 1; }
/usr/bin/plutil -lint "$APP/Contents/Info.plist" "$HELPER/Contents/Info.plist" "$INTENTS/Contents/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
for product in "$HELPER" "$INTENTS"; do
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$product/Contents/Info.plist")" == "$VERSION" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$product/Contents/Info.plist")" == "$BUILD" ]]
done

if "$UNSIGNED"; then
    SHA_VALUE="$SHA" ARCHIVE_VALUE="$ARCHIVE" VERSION_VALUE="$VERSION" /usr/bin/ruby -rjson -e '
      document = {
        commit_sha: ENV.fetch("SHA_VALUE"), version: ENV.fetch("VERSION_VALUE"),
        unsigned_archive: ENV.fetch("ARCHIVE_VALUE"), archive_topology_validated: true,
        externally_blocked: [
          "Developer ID signing and App Group provisioning profiles",
          "Apple notarization and stapling",
          "signed clean-install and update-from-previous validation"
        ]
      }
      File.write(ARGV.fetch(0), JSON.pretty_generate(document) + "\n")
    ' "$RELEASE_ROOT/distribution-boundaries.json"
    printf 'PASS: unsigned exact-candidate archive topology validated\n'
    printf 'NOT DISTRIBUTABLE: use the credentialed release path for signing, notarization, Sparkle, and packaging\n'
    exit 0
fi

[[ -n "$NOTARY_PROFILE" ]] || { printf 'error: signed release requires --notary-profile or BARLINE_NOTARY_PROFILE\n' >&2; exit 2; }

for product in "$APP" "$HELPER" "$INTENTS"; do
    codesign --verify --strict --verbose=2 "$product"
    authority="$(codesign -dv --verbose=4 "$product" 2>&1)"
    grep -q 'Authority=Developer ID Application: Mabry Ventures LLC (A886EMZZW6)' <<<"$authority" || {
        printf 'error: %s is not signed by the required Developer ID identity\n' "$product" >&2
        exit 1
    }
done
codesign --verify --deep --strict --verbose=2 "$APP"

APP_ENTITLEMENTS="$RELEASE_ROOT/app-entitlements.plist"
INTENTS_ENTITLEMENTS="$RELEASE_ROOT/intents-entitlements.plist"
codesign -d --entitlements "$APP_ENTITLEMENTS" "$APP"
codesign -d --entitlements "$INTENTS_ENTITLEMENTS" "$INTENTS"
for entitlements in "$APP_ENTITLEMENTS" "$INTENTS_ENTITLEMENTS"; do
    plutil -extract com.apple.security.application-groups xml1 -o - "$entitlements" | grep -q 'group.com.mabryventures.Barline'
    if plutil -extract com.apple.security.get-task-allow raw -o - "$entitlements" 2>/dev/null | grep -q true; then
        printf 'error: release entitlement contains get-task-allow: %s\n' "$entitlements" >&2
        exit 1
    fi
done
[[ -s "$APP/Contents/embedded.provisionprofile" ]] || { printf 'error: App Group release profile is not embedded in the app\n' >&2; exit 1; }
[[ -s "$INTENTS/Contents/embedded.provisionprofile" ]] || { printf 'error: App Group release profile is not embedded in the Intents extension\n' >&2; exit 1; }

DIST="$RELEASE_ROOT/dist"
/bin/rm -rf "$DIST"
mkdir -p "$DIST"
ZIP="$DIST/Barline-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

env DEVELOPER_DIR="$DEVELOPER_PATH" xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$RELEASE_ROOT/notarization.json"
grep -Eq '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$RELEASE_ROOT/notarization.json" || { printf 'error: notarization was not accepted\n' >&2; exit 1; }
env DEVELOPER_DIR="$DEVELOPER_PATH" xcrun stapler staple "$APP"
env DEVELOPER_DIR="$DEVELOPER_PATH" xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
/bin/rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

SPARKLE_BIN="$RELEASE_DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN/sign_update" && -x "$SPARKLE_BIN/generate_appcast" ]] || {
    printf 'error: resolve packages/build once so Sparkle release tools are available\n' >&2
    exit 1
}
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$ZIP" > "$ZIP.sparkle-signature.txt"

cp "$ROOT/CHANGELOG.md" "$DIST/Barline-$VERSION.md"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/Mabry-Ventures/Barline/releases/download/v$VERSION/" \
    --link 'https://github.com/Mabry-Ventures/Barline' --embed-release-notes -o "$DIST/appcast.xml" "$DIST"

validate_exact_candidate
git -C "$ROOT" archive --format=tar.gz --prefix="Barline-$VERSION/" -o "$DIST/Barline-$VERSION-source.tar.gz" "$SHA"
"$ROOT/script/generate-spdx-sbom.rb" "$ROOT" "$VERSION" "$BUILD" "$SHA" "$DIST/Barline-$VERSION.spdx.json"
validate_exact_candidate
(cd "$DIST" && shasum -a 256 "Barline-$VERSION.zip" "Barline-$VERSION-source.tar.gz" "Barline-$VERSION.spdx.json" appcast.xml > SHA256SUMS)

printf 'PASS: signed, notarized, stapled, Gatekeeper-assessed release package generated at %s\n' "$DIST"
printf 'MANUAL RELEASE EVIDENCE STILL REQUIRED: clean install and update from the previous public Barline version\n'
