#!/bin/bash

set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_OUTPUT="${BARLINE_EVENT_DELIVERY_ARTIFACT_DIR:-$TASK_ROOT/.artifacts/tests/event-delivery}"

mkdir -p "$TASK_OUTPUT/module-cache"
xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -module-cache-path "$TASK_OUTPUT/module-cache" \
    "$TASK_ROOT/BarlineMenuService/WindowServer/HelperEventTap.swift" \
    "$TASK_ROOT/script/test-event-delivery.swift" \
    -o "$TASK_OUTPUT/test-event-delivery"
"$TASK_OUTPUT/test-event-delivery"
