#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-notch-overflow-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-notch-overflow-tests"

mkdir -p "$MODULE_CACHE"
xcrun swiftc \
    -module-cache-path "$MODULE_CACHE" \
    "$ROOT/Barline/MenuBar/BarlineShelf/NotchOverflowResolver.swift" \
    "$ROOT/script/test-notch-overflow.swift" \
    -o "$BINARY"
"$BINARY"
