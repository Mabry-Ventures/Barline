#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/barline-menu-bar-recovery-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-menu-bar-recovery-tests"

mkdir -p "$MODULE_CACHE"
xcrun swiftc \
    -module-cache-path "$MODULE_CACHE" \
    "$ROOT/Shared/Bridging/MenuBarRecoveryPolicy.swift" \
    "$ROOT/script/test-menu-bar-recovery.swift" \
    -o "$BINARY"
"$BINARY"
