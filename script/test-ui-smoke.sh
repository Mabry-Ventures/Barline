#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.artifacts/run/DerivedData/Build/Products/Debug/Barline.app"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-ui-smoke-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-ui-smoke"

cleanup() {
    /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
    /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$ROOT/script/build_and_run.sh" --verify
/usr/bin/open -a "$APP"
/bin/sleep 0.5

mkdir -p "$MODULE_CACHE"
xcrun swiftc -module-cache-path "$MODULE_CACHE" \
    -framework AppKit -framework CoreGraphics \
    "$ROOT/script/test-ui-smoke.swift" -o "$BINARY"
"$BINARY" "$APP" com.mabryventures.Barline
