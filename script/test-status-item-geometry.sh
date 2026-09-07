#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/barline-status-geometry.XXXXXX")"
trap '/bin/rm -f "$TASK_DIR/probe"; /bin/rmdir "$TASK_DIR"' EXIT
swiftc "$ROOT/script/StatusItemFrameMatching.swift" "$ROOT/script/status-item-frame-tests.swift" -o "$TASK_DIR/probe"
"$TASK_DIR/probe"
