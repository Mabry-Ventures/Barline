#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=script/lib/identity.sh
source "$ROOT/script/lib/identity.sh"
APP_NAME=Barline
HELPER_NAME=BarlineMenuService
REUSE_RUNNING=false
RECOVERY_PROBE="runtime-smoke"
APP_PID=""

usage() {
    printf 'usage: %s [--reuse-running] [--recovery-probe runtime-smoke|apple-event-reopen]\n' "$0"
}

while (($#)); do
    case "$1" in
        --reuse-running) REUSE_RUNNING=true ;;
        --recovery-probe)
            (($# >= 2)) || { usage >&2; exit 2; }
            RECOVERY_PROBE="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

[[ "$RECOVERY_PROBE" == runtime-smoke || "$RECOVERY_PROBE" == apple-event-reopen ]] || { usage >&2; exit 2; }

cleanup() {
    if ! "$REUSE_RUNNING"; then
        /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        /usr/bin/pkill -x "$HELPER_NAME" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if "$REUSE_RUNNING"; then
    APP_PID="$(/usr/bin/pgrep -x "$APP_NAME" | head -1 || true)"
    [[ -n "$APP_PID" ]] || {
        printf 'error: --reuse-running requires an active Barline process\n' >&2
        exit 1
    }
else
    "$ROOT/script/build_and_run.sh" --verify
fi

helper_pid=""
for _ in {1..40}; do
    helper_pid="$(/usr/bin/pgrep -x "$HELPER_NAME" | head -1 || true)"
    [[ -z "$helper_pid" ]] || break
    /bin/sleep 0.25
done
if [[ -z "$helper_pid" ]]; then
    printf 'error: embedded XPC helper did not start; required app permissions may be unavailable, so interruption recovery is not verified\n' >&2
    exit 1
fi

/bin/kill -KILL "$helper_pid"
for _ in {1..20}; do
    /bin/kill -0 "$helper_pid" >/dev/null 2>&1 || break
    /bin/sleep 0.1
done
if /bin/kill -0 "$helper_pid" >/dev/null 2>&1; then
    printf 'error: XPC helper did not terminate for the forced interruption probe\n' >&2
    exit 1
fi
/usr/bin/pgrep -x "$APP_NAME" >/dev/null || {
    printf 'error: Barline terminated when its XPC helper was interrupted\n' >&2
    exit 1
}

if "$REUSE_RUNNING"; then
    if [[ "$RECOVERY_PROBE" == apple-event-reopen ]]; then
        BARLINE_PERFORMANCE_CYCLES=1 BARLINE_PERFORMANCE_WARMUPS=1 \
            "$ROOT/script/test-performance-smoke.sh" --reuse-running --probe apple-event-reopen
    else
        # Exercise the DEBUG-only user path in the development interruption gate.
        APP_BUNDLE_ID="$(barline_resolve_app_bundle_identifier "$ROOT" Debug)"
        BARLINE_NOTIFICATION_NAME="$APP_BUNDLE_ID.runtime-smoke.toggle-shelf" xcrun swift -e '
          import Foundation
          let name = ProcessInfo.processInfo.environment["BARLINE_NOTIFICATION_NAME"]!
          DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true
          )
        '
    fi
fi

replacement_pid=""
for _ in {1..40}; do
    replacement_pid="$(/usr/bin/pgrep -x "$HELPER_NAME" | head -1 || true)"
    if [[ -n "$replacement_pid" && "$replacement_pid" != "$helper_pid" ]]; then
        break
    fi
    /bin/sleep 0.25
done
if [[ -z "$replacement_pid" || "$replacement_pid" == "$helper_pid" ]]; then
    printf 'error: XPC helper was not relaunched while Barline remained running; interruption recovery is incomplete\n' >&2
    exit 1
fi
if [[ -n "$APP_PID" && "$(/usr/bin/pgrep -x "$APP_NAME" | head -1 || true)" != "$APP_PID" ]]; then
    printf 'error: Barline changed processes during XPC recovery; RSS continuity is invalid\n' >&2
    exit 1
fi

printf 'PASS: XPC helper interruption preserved the app and produced a replacement helper process\n'
