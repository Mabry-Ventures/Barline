#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-performance-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-shelf-responsiveness"
PREFERENCE_DOMAIN="com.mabryventures.Barline"
PREFERENCE_KEY="UseBarlineShelf"
ORIGINAL_PREFERENCE="__missing__"
REUSE_RUNNING=false
OUTPUT_PATH=""
PROBE="${BARLINE_PERFORMANCE_PROBE:-runtime-smoke}"

usage() {
    printf 'usage: %s [--reuse-running] [--probe runtime-smoke|apple-event-reopen] [--output PATH]\n' "$0" >&2
}

while (($#)); do
    case "$1" in
        --reuse-running) REUSE_RUNNING=true ;;
        --probe)
            (($# >= 2)) || { usage; exit 2; }
            PROBE="$2"
            shift
            ;;
        --output)
            (($# >= 2)) || { usage; exit 2; }
            OUTPUT_PATH="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
    shift
done

[[ "$PROBE" == runtime-smoke || "$PROBE" == apple-event-reopen ]] || { usage; exit 2; }

if ORIGINAL_PREFERENCE_VALUE="$(/usr/bin/defaults read "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" 2>/dev/null)"; then
    ORIGINAL_PREFERENCE="$ORIGINAL_PREFERENCE_VALUE"
fi

cleanup() {
    if ! "$REUSE_RUNNING"; then
        /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
        /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
    fi
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

if "$REUSE_RUNNING"; then
    /usr/bin/pgrep -x Barline >/dev/null || {
        printf 'error: --reuse-running requires an active Barline process\n' >&2
        exit 1
    }
else
    /usr/bin/defaults write "$PREFERENCE_DOMAIN" "$PREFERENCE_KEY" -bool true
    BARLINE_RUNTIME_SMOKE=1 "$ROOT/script/build_and_run.sh" --verify
fi
mkdir -p "$MODULE_CACHE"
xcrun swiftc -module-cache-path "$MODULE_CACHE" \
    -framework AppKit -framework CoreGraphics \
    "$ROOT/script/measure-barline-shelf-responsiveness.swift" -o "$BINARY"
if [[ -n "$OUTPUT_PATH" ]]; then
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    BARLINE_PERFORMANCE_PROBE="$PROBE" "$BINARY" | tee -a "$OUTPUT_PATH"
else
    BARLINE_PERFORMANCE_PROBE="$PROBE" "$BINARY"
fi
