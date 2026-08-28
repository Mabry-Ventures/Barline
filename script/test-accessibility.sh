#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.artifacts/run/DerivedData/Build/Products/Debug/Barline.app"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-accessibility-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-accessibility-audit"

cleanup() {
    /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
    /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Source-level regression assertions for the custom, icon-driven controls.
rg -q '\.accessibilityLabel\(item\.displayName\)' "$ROOT/Barline/MenuBar/BarlineShelf/BarlineShelf.swift"
rg -q '\.accessibilityAction\(named: "left click"' "$ROOT/Barline/MenuBar/BarlineShelf/BarlineShelf.swift"
rg -q '\.accessibilityAction\(named: "right click"' "$ROOT/Barline/MenuBar/BarlineShelf/BarlineShelf.swift"
rg -q '\.accessibilityLabel\(label\)' "$ROOT/Barline/UI/Views/HotkeyRecorder.swift"

"$ROOT/script/build_and_run.sh" --verify
/usr/bin/open -a "$APP"
/bin/sleep 0.5

pid="$(/usr/bin/pgrep -x Barline | head -1)"
[[ -n "$pid" ]] || { printf 'error: Barline is not running\n' >&2; exit 1; }

mkdir -p "$MODULE_CACHE"
xcrun swiftc -module-cache-path "$MODULE_CACHE" \
    -framework ApplicationServices \
    "$ROOT/script/test-accessibility.swift" -o "$BINARY"
"$BINARY" "$pid"
