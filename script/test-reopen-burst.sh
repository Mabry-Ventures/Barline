#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=script/lib/identity.sh
source "$ROOT/script/lib/identity.sh"

export BARLINE_BUILD_CONFIGURATION=Release
BARLINE_APP_BUNDLE_IDENTIFIER="$(
    barline_resolve_app_bundle_identifier "$ROOT" "$BARLINE_BUILD_CONFIGURATION"
)"
export BARLINE_APP_BUNDLE_IDENTIFIER

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

# The release soak also interleaves helper interruption with reopen requests.
# Keep a bounded version in the full gate so cross-path work accumulation fails
# quickly instead of appearing only in the 30-minute candidate run.
for cycle in {1..8}; do
    if ((cycle > 1)); then
        # launchd deliberately throttles services that are SIGKILLed in a tight
        # crash loop. Keep each forced interruption independent so this gate
        # measures Barline recovery rather than the host's crash-loop backoff;
        # the release soak naturally provides at least this spacing as well.
        /bin/sleep 10
    fi
    printf 'Recovery/reopen burst cycle %d\n' "$cycle"
    "$ROOT/script/test-xpc-interruption.sh" \
        --reuse-running --recovery-probe apple-event-reopen
    BARLINE_PERFORMANCE_CYCLES=5 BARLINE_PERFORMANCE_WARMUPS=1 \
        "$ROOT/script/test-performance-smoke.sh" --reuse-running --probe apple-event-reopen
done
