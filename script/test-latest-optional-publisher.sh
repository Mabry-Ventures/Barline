#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/barline-latest-owner.XXXXXX")"
trap '/bin/rm -f "$TASK_DIR/probe"; /bin/rmdir "$TASK_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    "$ROOT/Barline/Utilities/LatestOptionalPublisher.swift" \
    "$ROOT/script/tests/LatestOptionalPublisherProbe.swift" -o "$TASK_DIR/probe"
"$TASK_DIR/probe"
