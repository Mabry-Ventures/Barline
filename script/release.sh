#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_PATH="${DEVELOPER_DIR:-$(xcode-select -p)}"
SHA="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ROOT="$ROOT/.artifacts/release/$SHA"
ARCHIVE="$RELEASE_ROOT/Barline.xcarchive"
RELEASE_DERIVED_DATA="$RELEASE_ROOT/DerivedData"
SIGNING_SCRATCH=""
EXPORT_PATH=""
EXPORT_OPTIONS=""
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

if ! "$UNSIGNED"; then
    [[ -n "$NOTARY_PROFILE" ]] || { printf 'error: signed release requires --notary-profile or BARLINE_NOTARY_PROFILE\n' >&2; exit 2; }
    SIGNING_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/barline-release.${SHA}.XXXXXX")"
    ARCHIVE="$SIGNING_SCRATCH/Barline.xcarchive"
    RELEASE_DERIVED_DATA="$SIGNING_SCRATCH/DerivedData"
    EXPORT_PATH="$SIGNING_SCRATCH/Export"
    EXPORT_OPTIONS="$SIGNING_SCRATCH/ExportOptions.plist"
    trap '[[ -z "$SIGNING_SCRATCH" ]] || /bin/rm -rf -- "$SIGNING_SCRATCH"' EXIT
fi

for command in xcodebuild codesign ditto plutil ruby shasum security openssl base64 date; do
    command -v "$command" >/dev/null 2>&1 || { printf 'error: missing %s\n' "$command" >&2; exit 1; }
done
for required in LICENSE NOTICE.md THIRD_PARTY_NOTICES.md PRIVACY.md SECURITY.md docs/PROVENANCE.md docs/BUILDING.md; do
    [[ -s "$ROOT/$required" ]] || { printf 'error: required distribution file is missing or empty: %s\n' "$required" >&2; exit 1; }
done

mkdir -p "$RELEASE_ROOT"
/bin/rm -rf "$ARCHIVE" "$RELEASE_DERIVED_DATA" "$RELEASE_ROOT/distribution-boundaries.json"
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

if "$UNSIGNED"; then
    APP="$ARCHIVE/Products/Applications/Barline.app"
else
    # A Developer ID archive alone does not distribution-sign Sparkle's nested
    # updater executables. Xcode's export step signs the full nested graph with
    # timestamps before the release gate validates or submits the app.
    plutil -create xml1 "$EXPORT_OPTIONS"
    plutil -insert method -string developer-id "$EXPORT_OPTIONS"
    plutil -insert destination -string export "$EXPORT_OPTIONS"
    plutil -insert signingStyle -string manual "$EXPORT_OPTIONS"
    plutil -insert teamID -string A886EMZZW6 "$EXPORT_OPTIONS"
    plutil -insert signingCertificate -string D3F13221A5E8B4D1E6FE0888B063B62344101B87 "$EXPORT_OPTIONS"
    plutil -insert provisioningProfiles -dictionary "$EXPORT_OPTIONS"
    /usr/libexec/PlistBuddy -c \
        "Add :provisioningProfiles:com.mabryventures.Barline string 'Barline Developer ID D3F13221'" \
        "$EXPORT_OPTIONS"
    /usr/libexec/PlistBuddy -c \
        "Add :provisioningProfiles:com.mabryventures.Barline.Intents string 'Barline Intents Developer ID D3F13221'" \
        "$EXPORT_OPTIONS"
    env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild \
        -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS"
    APP="$EXPORT_PATH/Barline.app"
fi
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
validate_exact_candidate

if "$UNSIGNED"; then
    END_SHA="$(git -C "$ROOT" rev-parse HEAD)"
    SHA_VALUE="$SHA" END_SHA_VALUE="$END_SHA" ARCHIVE_VALUE="$ARCHIVE" VERSION_VALUE="$VERSION" /usr/bin/ruby -rjson -e '
      document = {
        start_commit_sha: ENV.fetch("SHA_VALUE"), end_commit_sha: ENV.fetch("END_SHA_VALUE"),
        clean_at_end: true, exact_candidate_revalidated_after_archive: true,
        version: ENV.fetch("VERSION_VALUE"),
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

SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/Current"
SIGNED_CODE=(
    "$APP"
    "$HELPER"
    "$INTENTS"
    "$SPARKLE_FRAMEWORK"
    "$SPARKLE_VERSION/Updater.app"
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    "$SPARKLE_VERSION/Autoupdate"
)
for product in "${SIGNED_CODE[@]}"; do
    [[ -e "$product" ]] || { printf 'error: signed archive is missing nested code: %s\n' "$product" >&2; exit 1; }
    codesign --verify --strict --verbose=2 "$product"
    authority="$(codesign -dv --verbose=4 "$product" 2>&1)"
    grep -q 'Authority=Developer ID Application: Mabry Ventures LLC (A886EMZZW6)' <<<"$authority" || {
        printf 'error: %s is not signed by the required Developer ID identity\n' "$product" >&2
        exit 1
    }
    grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' <<<"$authority" || {
        printf 'error: %s is missing Hardened Runtime\n' "$product" >&2
        exit 1
    }
done
codesign --verify --deep --strict --verbose=2 "$APP"

APP_ENTITLEMENTS="$RELEASE_ROOT/app-entitlements.plist"
INTENTS_ENTITLEMENTS="$RELEASE_ROOT/intents-entitlements.plist"
codesign -d --entitlements - --xml "$APP" > "$APP_ENTITLEMENTS"
codesign -d --entitlements - --xml "$INTENTS" > "$INTENTS_ENTITLEMENTS"
for entitlements in "$APP_ENTITLEMENTS" "$INTENTS_ENTITLEMENTS"; do
    plutil -extract com.apple.security.application-groups xml1 -o - "$entitlements" | grep -q 'group.com.mabryventures.Barline'
    if plutil -extract com.apple.security.get-task-allow raw -o - "$entitlements" 2>/dev/null | grep -q true; then
        printf 'error: release entitlement contains get-task-allow: %s\n' "$entitlements" >&2
        exit 1
    fi
done
SIGNING_CERT_PREFIX="$SIGNING_SCRATCH/barline-signing-cert"
codesign -d --extract-certificates "$SIGNING_CERT_PREFIX" "$APP"
SIGNING_CERT_FINGERPRINT="$(openssl x509 -inform DER -in "${SIGNING_CERT_PREFIX}0" -noout -fingerprint -sha1 | cut -d= -f2)"

validate_embedded_profile() {
    local product="$1" expected_application_identifier="$2" label="$3"
    local profile="$product/Contents/embedded.provisionprofile"
    local decoded="$SIGNING_SCRATCH/${label}-profile.plist"
    local expiration expiration_epoch now_epoch profile_fingerprint groups

    [[ -s "$profile" ]] || { printf 'error: %s release profile is not embedded\n' "$label" >&2; return 1; }
    security cms -D -i "$profile" > "$decoded"
    [[ "$(plutil -extract TeamIdentifier.0 raw -o - "$decoded")" == A886EMZZW6 ]] || {
        printf 'error: %s profile has the wrong team\n' "$label" >&2; return 1;
    }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$decoded")" == "$expected_application_identifier" ]] || {
        printf 'error: %s profile has the wrong application identifier\n' "$label" >&2; return 1;
    }
    groups="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' "$decoded")"
    grep -Fxq '    group.com.mabryventures.Barline' <<<"$groups" || {
        printf 'error: %s profile is missing the Barline App Group\n' "$label" >&2; return 1;
    }
    [[ "$(plutil -extract ProvisionsAllDevices raw -o - "$decoded")" == true ]] || {
        printf 'error: %s profile is not a Developer ID distribution profile\n' "$label" >&2; return 1;
    }
    expiration="$(plutil -extract ExpirationDate raw -o - "$decoded")"
    expiration_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s')"
    now_epoch="$(date -u '+%s')"
    ((expiration_epoch > now_epoch)) || { printf 'error: %s profile is expired\n' "$label" >&2; return 1; }
    profile_fingerprint="$(plutil -extract DeveloperCertificates.0 raw -o - "$decoded" | base64 -D | openssl x509 -inform DER -noout -fingerprint -sha1 | cut -d= -f2)"
    [[ "$profile_fingerprint" == "$SIGNING_CERT_FINGERPRINT" ]] || {
        printf 'error: %s profile does not contain the archive signing certificate\n' "$label" >&2; return 1;
    }
}

validate_embedded_profile "$APP" 'A886EMZZW6.com.mabryventures.Barline' app
validate_embedded_profile "$INTENTS" 'A886EMZZW6.com.mabryventures.Barline.Intents' intents

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
