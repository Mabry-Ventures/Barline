#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
    /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
    /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Reopen is a production recovery path. Exercise enough requests in one
# process to detect delayed-window or compatibility-refresh work accumulating
# on the main actor.
"$ROOT/script/build_and_run.sh" --release --verify
BARLINE_PERFORMANCE_CYCLES=100 BARLINE_PERFORMANCE_WARMUPS=5 \
    "$ROOT/script/test-performance-smoke.sh" --reuse-running --probe apple-event-reopen
