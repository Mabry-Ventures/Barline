#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /private/tmp/barline-permission-tests.XXXXXX)"
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    "$ROOT/Barline/Permissions/Permission.swift" \
    "$ROOT/script/test-permission-refresh.swift" \
    -o "$TEST_DIR/permission-refresh"
"$TEST_DIR/permission-refresh"
