#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/barline-shelf-cycle.XXXXXX")"
trap '/bin/rm -f "$TASK_DIR/probe"; /bin/rmdir "$TASK_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    "$ROOT/script/ConcurrentObservation.swift" \
    "$ROOT/script/ShelfProbeCycle.swift" \
    "$ROOT/script/test-shelf-probe-cycle.swift" \
    -o "$TASK_DIR/probe"
"$TASK_DIR/probe"
