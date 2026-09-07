#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=script/lib/identity.sh
source "$ROOT/script/lib/identity.sh"

export BARLINE_BUILD_CONFIGURATION=Release
REUSE_RUNNING=false
if [[ "${1:-}" == --reuse-running && $# == 1 ]]; then
    REUSE_RUNNING=true
elif (($#)); then
    printf 'usage: %s [--reuse-running]\n' "$0" >&2
    exit 2
fi
BARLINE_APP_BUNDLE_IDENTIFIER="$(
    barline_resolve_app_bundle_identifier "$ROOT" "$BARLINE_BUILD_CONFIGURATION"
)"
export BARLINE_APP_BUNDLE_IDENTIFIER

cleanup() {
    if ! "$REUSE_RUNNING"; then
        /usr/bin/pkill -x Barline >/dev/null 2>&1 || true
        /usr/bin/pkill -x BarlineMenuService >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# Keep the historical gate filename but exercise the actual nonactivating shelf
# path. Repeated AppleEvent reopen deliberately raises Settings and violates the
# user's foreground policy. This test does not claim AppleEvent/Settings coverage.
# The signed-candidate installed journey separately proves target interaction.
if ! "$REUSE_RUNNING"; then
    BARLINE_PRODUCTION_LAUNCH=1 "$ROOT/script/build_and_run.sh" --release --verify
fi
BARLINE_PERFORMANCE_CYCLES=20 BARLINE_PERFORMANCE_WARMUPS=1 \
    "$ROOT/script/test-performance-smoke.sh" --reuse-running --probe status-item-click

# One forced helper interruption followed by five real opens proves same-process
# recovery without a synthetic crash loop or repeated focus changes. Sustained
# recovery/soak is a separate lane, explicitly deferred by the user.
"$ROOT/script/test-xpc-interruption.sh" \
    --reuse-running --recovery-probe status-item-click
BARLINE_PERFORMANCE_CYCLES=5 BARLINE_PERFORMANCE_WARMUPS=1 \
    "$ROOT/script/test-performance-smoke.sh" --reuse-running --probe status-item-click
printf 'PASS: nonactivating shelf burst and one helper recovery; Settings reopen and soak are separate lanes\n'
