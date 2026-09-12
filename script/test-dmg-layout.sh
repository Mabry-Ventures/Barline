#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/lib/dmg.sh
source "$SCRIPT_DIR/lib/dmg.sh"

command -v hdiutil >/dev/null 2>&1 || { printf 'dmg layout: hdiutil is required\n' >&2; exit 1; }
WORK="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/barline-dmg-layout.XXXXXX")"
trap '/bin/rm -rf "$WORK"' EXIT
cases=0

fail() {
    printf 'dmg layout: %s\n' "$*" >&2
    exit 1
}

pass() {
    cases=$((cases + 1))
}

make_app() {
    local app="$1"
    mkdir -p "$app/Contents/MacOS"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' >"$app/Contents/Info.plist"
    printf 'fixture\n' >"$app/Contents/MacOS/Fixture"
}

# Builds an image from an arbitrary staged folder to exercise layouts that
# barline_build_dmg itself never produces.
make_raw_dmg() {
    local folder="$1" dmg="$2"
    /usr/bin/hdiutil create -quiet -volname Fixture -srcfolder "$folder" -fs HFS+ -format UDZO "$dmg"
}

APP="$WORK/Barline.app"
make_app "$APP"

barline_build_dmg "$APP" "$WORK/good.dmg" Barline || fail "valid app did not build"
barline_require_dmg_layout "$WORK/good.dmg" Barline.app || fail "valid image was rejected"
pass

if barline_build_dmg "$APP" "$WORK/good.dmg" Barline 2>/dev/null; then
    fail "existing image was overwritten"
fi
pass

mkdir -p "$WORK/not-an-app"
if barline_build_dmg "$WORK/not-an-app" "$WORK/not-an-app.dmg" Barline 2>/dev/null; then
    fail "non-app input produced an image"
fi
[[ ! -e "$WORK/not-an-app.dmg" ]] || fail "rejected input left an image behind"
pass

mkdir -p "$WORK/no-link"
/usr/bin/ditto "$APP" "$WORK/no-link/Barline.app"
make_raw_dmg "$WORK/no-link" "$WORK/no-link.dmg"
if barline_require_dmg_layout "$WORK/no-link.dmg" Barline.app 2>/dev/null; then
    fail "image without an Applications shortcut was accepted"
fi
pass

mkdir -p "$WORK/wrong-link"
/usr/bin/ditto "$APP" "$WORK/wrong-link/Barline.app"
/bin/ln -s /tmp "$WORK/wrong-link/Applications"
make_raw_dmg "$WORK/wrong-link" "$WORK/wrong-link.dmg"
if barline_require_dmg_layout "$WORK/wrong-link.dmg" Barline.app 2>/dev/null; then
    fail "Applications shortcut to the wrong target was accepted"
fi
pass

mkdir -p "$WORK/extra"
/usr/bin/ditto "$APP" "$WORK/extra/Barline.app"
/bin/ln -s /Applications "$WORK/extra/Applications"
printf 'unexpected\n' >"$WORK/extra/README.txt"
make_raw_dmg "$WORK/extra" "$WORK/extra.dmg"
if barline_require_dmg_layout "$WORK/extra.dmg" Barline.app 2>/dev/null; then
    fail "image with an unexpected entry was accepted"
fi
pass

mkdir -p "$WORK/missing-app"
/bin/ln -s /Applications "$WORK/missing-app/Applications"
make_raw_dmg "$WORK/missing-app" "$WORK/missing-app.dmg"
if barline_require_dmg_layout "$WORK/missing-app.dmg" Barline.app 2>/dev/null; then
    fail "image without the app bundle was accepted"
fi
pass

[[ -z "$(/usr/bin/hdiutil info | grep -F "$WORK" || true)" ]] || fail "a fixture image was left mounted"
pass

# Appcast enclosure checks. Release notes are embedded in the appcast, and the
# release that introduces the disk image will mention it, so prose must never
# fail an otherwise valid appcast.
ZIP_URL="https://github.com/Mabry-Ventures/mv-barline/releases/download/v9.8.7/Barline-9.8.7.zip"
appcast() {
    printf '<?xml version="1.0"?><rss><channel><item><title>9.8.7</title>%s</item></channel></rss>\n' "$1"
}
enclosure_cases=0
appcast "<description><![CDATA[<li>Download Barline-9.8.7.dmg to install.</li>]]></description><enclosure url=\"$ZIP_URL\" sparkle:version=\"1\" length=\"1\" type=\"application/octet-stream\"/>" >"$WORK/notes.xml"
barline_require_zip_enclosures "$WORK/notes.xml" "$ZIP_URL" || fail "release notes mentioning the disk image failed a valid appcast"
enclosure_cases=$((enclosure_cases + 1))

appcast "<enclosure sparkle:version=\"1\" url=\"$ZIP_URL\" length=\"1\"/>" >"$WORK/reordered.xml"
barline_require_zip_enclosures "$WORK/reordered.xml" "$ZIP_URL" || fail "an enclosure with url after other attributes was rejected"
enclosure_cases=$((enclosure_cases + 1))

for bad in \
    "<enclosure url=\"${ZIP_URL%.zip}.dmg\" length=\"1\"/>" \
    "<enclosure url=\"$ZIP_URL\" length=\"1\"/><enclosure url=\"${ZIP_URL%.zip}.dmg\" length=\"1\"/>" \
    "<enclosure url=\"https://github.com/Mabry-Ventures/mv-barline/releases/download/v9.8.6/Barline-9.8.6.zip\" length=\"1\"/>" \
    "<description>No enclosure at all.</description>"; do
    appcast "$bad" >"$WORK/bad.xml"
    if barline_require_zip_enclosures "$WORK/bad.xml" "$ZIP_URL" 2>/dev/null; then
        fail "an unsafe appcast enclosure was accepted: $bad"
    fi
    enclosure_cases=$((enclosure_cases + 1))
done

printf 'PASS: DMG layout builds the app beside an Applications shortcut and rejects %d malformed or unsafe cases; %d appcast enclosure cases\n' "$((cases - 2))" "$enclosure_cases"
