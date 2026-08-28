#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-performance-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-shelf-responsiveness"
PREFERENCE_DOMAIN="com.mabryventures.Barline"
PREFERENCE_KEY="UseBarlineShelf"
ORIGINAL_PREFERENCE="__missing__"

if ORIGINAL_PREFERENCE_VALUE="$(/usr/bin/defaults read "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" 2>/dev/null)"; then
    ORIGINAL_PREFERENCE="$ORIGINAL_PREFERENCE_VALUE"
fi

cleanup() {
    /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
    /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
    if [[ "$ORIGINAL_PREFERENCE" == "__missing__" ]]; then
        /usr/bin/defaults delete "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" >/dev/null 2>&1 || true
    else
        if [[ "$ORIGINAL_PREFERENCE" == "1" ]]; then
            /usr/bin/defaults write "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" -bool true
        else
            /usr/bin/defaults write "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" -bool false
        fi
    fi
}
trap cleanup EXIT

/usr/bin/defaults write "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" -bool true
BARLINE_RUNTIME_SMOKE=1 "$ROOT/script/build_and_run.sh" --verify
mkdir -p "$MODULE_CACHE"
xcrun swiftc -module-cache-path "$MODULE_CACHE" \
    -framework AppKit -framework CoreGraphics \
    "$ROOT/script/measure-barline-shelf-responsiveness.swift" -o "$BINARY"
"$BINARY"
