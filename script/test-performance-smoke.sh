#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=script/lib/identity.sh
source "$ROOT/script/lib/identity.sh"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-performance-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-shelf-responsiveness"
PREFERENCE_DOMAIN=""
PREFERENCE_KEY="UseBarlineShelf"
ORIGINAL_PREFERENCE="__missing__"
REUSE_RUNNING=false
OUTPUT_PATH=""
PROBE="${BARLINE_PERFORMANCE_PROBE:-runtime-smoke}"
BUILD_CONFIGURATION="${BARLINE_BUILD_CONFIGURATION:-Debug}"

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
[[ "$BUILD_CONFIGURATION" == Debug || "$BUILD_CONFIGURATION" == Release ]] || {
    printf 'error: BARLINE_BUILD_CONFIGURATION must be Debug or Release\n' >&2
    exit 2
}

if [[ -n "${BARLINE_APP_BUNDLE_IDENTIFIER:-}" ]]; then
    barline_validate_bundle_identifier "$BARLINE_APP_BUNDLE_IDENTIFIER" || {
        printf 'error: inherited BARLINE_APP_BUNDLE_IDENTIFIER is invalid\n' >&2
        exit 1
    }
    PREFERENCE_DOMAIN="$BARLINE_APP_BUNDLE_IDENTIFIER"
else
    PREFERENCE_DOMAIN="$(barline_resolve_app_bundle_identifier "$ROOT" "$BUILD_CONFIGURATION")"
fi

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
    if [[ "$BUILD_CONFIGURATION" == Release ]]; then
        BARLINE_APP_BUNDLE_IDENTIFIER="$PREFERENCE_DOMAIN" BARLINE_RUNTIME_SMOKE=1 \
            "$ROOT/script/build_and_run.sh" --release --verify
    else
        BARLINE_APP_BUNDLE_IDENTIFIER="$PREFERENCE_DOMAIN" BARLINE_RUNTIME_SMOKE=1 \
            "$ROOT/script/build_and_run.sh" --verify
    fi
fi
APP_PID="$(/usr/bin/pgrep -x Barline | /usr/bin/head -1 || true)"
[[ -n "$APP_PID" ]] || {
    printf 'error: Barline process is unavailable for the responsiveness probe\n' >&2
    exit 1
}
mkdir -p "$MODULE_CACHE"
xcrun swiftc -module-cache-path "$MODULE_CACHE" \
    -framework AppKit -framework CoreGraphics \
    "$ROOT/script/measure-barline-shelf-responsiveness.swift" -o "$BINARY"
if [[ -n "$OUTPUT_PATH" ]]; then
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    BARLINE_APP_BUNDLE_IDENTIFIER="$PREFERENCE_DOMAIN" \
        BARLINE_EXPECTED_PID="$APP_PID" BARLINE_PERFORMANCE_PROBE="$PROBE" \
        "$BINARY" | tee -a "$OUTPUT_PATH"
else
    BARLINE_APP_BUNDLE_IDENTIFIER="$PREFERENCE_DOMAIN" \
        BARLINE_EXPECTED_PID="$APP_PID" BARLINE_PERFORMANCE_PROBE="$PROBE" "$BINARY"
fi
