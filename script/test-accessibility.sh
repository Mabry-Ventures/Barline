#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/barline-accessibility.XXXXXX")"
APP="$DERIVED_DATA/Build/Products/Debug/BarlineFixture.app"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-accessibility-module-cache"
AUDIT_APP="${BARLINE_ACCESSIBILITY_AUDIT_APP:-${HOME}/Library/Application Support/Barline/Testing/BarlineAccessibilityAudit.app}"
BINARY="$AUDIT_APP/Contents/MacOS/BarlineAccessibilityAudit"

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
rg -q 'appState\.performSetup\(\)' "$ROOT/Barline/Main/AppDelegate.swift"
if rg -q 'performSetup\(hasPermissions:' "$ROOT/Barline"; then
    printf 'error: launch still branches setup on permission state\n' >&2
    exit 1
fi
if rg -q 'permissions\.stopAllChecks\(\)' "$ROOT/Barline/Main/AppState.swift"; then
    printf 'error: app setup disables permission transition observation\n' >&2
    exit 1
fi
rg -q 'permissions\.accessibility\.\$hasPermission' "$ROOT/Barline/Main/AppState.swift"
rg -q 'let initialAccessibilityPermission = permissions\.accessibility\.hasPermission' "$ROOT/Barline/Main/AppState.swift"
rg -q 'startsEnabled: initialAccessibilityPermission' "$ROOT/Barline/Main/AppState.swift"
rg -q 'accessibilityIdentifier\("degraded-mode-banner"\)' "$ROOT/Barline/Settings/SettingsView.swift"

env DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}" xcodebuild \
    -project "$ROOT/Barline.xcodeproj" -scheme BarlineFixture -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet build
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP"
/usr/bin/pkill -x BarlineFixture >/dev/null 2>&1 || true
for ((attempt = 0; attempt < 20; attempt++)); do
    /usr/bin/pgrep -x BarlineFixture >/dev/null 2>&1 || break
    /bin/sleep 0.1
done
if /usr/bin/pgrep -x BarlineFixture >/dev/null 2>&1; then
    printf 'error: stale BarlineFixture did not terminate\n' >&2
    exit 1
fi
/usr/bin/open -g -n "$APP" --args --barline-fixture-accessibility-audit

pid=""
for ((attempt = 0; attempt < 50; attempt++)); do
    pid="$(/usr/bin/pgrep -x BarlineFixture | /usr/bin/head -1 || true)"
    [[ -z "$pid" ]] || break
    /bin/sleep 0.1
done
[[ -n "$pid" ]] || { printf 'error: BarlineFixture is not running\n' >&2; exit 1; }

mkdir -p "$MODULE_CACHE"
mkdir -p "$AUDIT_APP/Contents/MacOS"
/bin/cp "$ROOT/script/BarlineAccessibilityAudit-Info.plist" "$AUDIT_APP/Contents/Info.plist"
xcrun swiftc -module-cache-path "$MODULE_CACHE" \
    -framework ApplicationServices \
    "$ROOT/script/test-accessibility.swift" -o "$BINARY"
/usr/bin/xattr -cr "$AUDIT_APP"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$AUDIT_APP"
"$BINARY" "$pid"
