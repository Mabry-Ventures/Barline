#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-performance-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-shelf-responsiveness"

cleanup() {
    /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
    /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$ROOT/script/build_and_run.sh" --verify
mkdir -p "$MODULE_CACHE"
xcrun swiftc -module-cache-path "$MODULE_CACHE" \
    -framework AppKit -framework CoreGraphics \
    "$ROOT/script/measure-barline-shelf-responsiveness.swift" -o "$BINARY"
"$BINARY"
