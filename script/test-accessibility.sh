#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/barline-accessibility.XXXXXX")"
APP="$DERIVED_DATA/Build/Products/Debug/BarlineFixture.app"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-accessibility-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-accessibility-audit"

cleanup() {
    /usr/bin/pkill -x BarlineFixture >/dev/null 2>&1 || true
    /bin/rm -rf "$DERIVED_DATA"
}
trap cleanup EXIT

# Source-level regression assertions for the custom, icon-driven controls.
rg -q '\.accessibilityLabel\(item\.displayName\)' "$ROOT/Barline/MenuBar/BarlineShelf/BarlineShelf.swift"
rg -q '\.accessibilityAction\(named: "left click"' "$ROOT/Barline/MenuBar/BarlineShelf/BarlineShelf.swift"
rg -q '\.accessibilityAction\(named: "right click"' "$ROOT/Barline/MenuBar/BarlineShelf/BarlineShelf.swift"
rg -q '\.accessibilityLabel\(label\)' "$ROOT/Barline/UI/Views/HotkeyRecorder.swift"

env DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}" xcodebuild \
    -project "$ROOT/Barline.xcodeproj" -scheme BarlineFixture -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet build
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP"
/usr/bin/open -n "$APP"
/bin/sleep 1

pid="$(/usr/bin/pgrep -x BarlineFixture | head -1)"
[[ -n "$pid" ]] || { printf 'error: BarlineFixture is not running\n' >&2; exit 1; }

mkdir -p "$MODULE_CACHE"
xcrun swiftc -module-cache-path "$MODULE_CACHE" \
    -framework ApplicationServices \
    "$ROOT/script/test-accessibility.swift" -o "$BINARY"
"$BINARY" "$pid"
