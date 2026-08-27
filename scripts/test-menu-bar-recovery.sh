#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/ice-menu-bar-recovery-module-cache"
BINARY="${TMPDIR:-/tmp}/ice-menu-bar-recovery-tests"

mkdir -p "$MODULE_CACHE"
xcrun swiftc \
    -module-cache-path "$MODULE_CACHE" \
    "$ROOT/Shared/Bridging/MenuBarRecoveryPolicy.swift" \
    "$ROOT/scripts/test-menu-bar-recovery.swift" \
    -o "$BINARY"
"$BINARY"
