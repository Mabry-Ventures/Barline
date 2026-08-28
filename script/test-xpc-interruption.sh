#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME=Barline
HELPER_NAME=BarlineMenuService
REUSE_RUNNING=false

case "${1:-}" in
    "") ;;
    --reuse-running) REUSE_RUNNING=true ;;
    -h|--help)
        printf 'usage: %s [--reuse-running]\n' "$0"
        exit 0
        ;;
    *) printf 'usage: %s [--reuse-running]\n' "$0" >&2; exit 2 ;;
esac

cleanup() {
    if ! "$REUSE_RUNNING"; then
        /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        /usr/bin/pkill -x "$HELPER_NAME" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if "$REUSE_RUNNING"; then
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null || {
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
    # The long-running soak app has no launch-time work left to drive a new
    # request across the invalidated connection. Exercise its DEBUG-only
    # runtime-smoke action so recovery is measured on a real user path.
    xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.mabryventures.Barline.runtime-smoke.toggle-shelf"), object: nil, userInfo: nil, deliverImmediately: true)'
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

printf 'PASS: XPC helper interruption preserved the app and produced a replacement helper process\n'
