#!/usr/bin/env bash
set -euo pipefail
if (($# != 2)); then
    printf 'usage: %s /absolute/BarlineFixture.app /absolute/ignored-artifacts-directory\n' "$0" >&2
    exit 2
fi
FIXTURE_APP="$1"
ARTIFACT_DIR="$2"
[[ "$FIXTURE_APP" == /* && -x "$FIXTURE_APP/Contents/MacOS/BarlineFixture" && "$ARTIFACT_DIR" == /* ]] || exit 2
if /usr/bin/pgrep -x BarlineFixture >/dev/null; then
    printf 'error: a fixture is already running; refuse to create another instance\n' >&2
    exit 1
fi
mkdir -p "$ARTIFACT_DIR"
SESSION="$(/usr/bin/uuidgen)"
RECEIPT="$ARTIFACT_DIR/fixture-$SESSION.json"
# Background plus hidden prevents a WindowGroup launch from raising any window.
# The fixture itself switches to accessory and orders its windows out as well.
/usr/bin/open -g -j -n "$FIXTURE_APP" \
    --env BARLINE_FIXTURE_MODE=journey \
    --env "BARLINE_FIXTURE_SESSION=$SESSION" \
    --env "BARLINE_FIXTURE_RECEIPT=$RECEIPT" \
    --env "BARLINE_FIXTURE_JOURNEY_ITEMS=${BARLINE_FIXTURE_JOURNEY_ITEMS:-Native,Popover}"
for _ in {1..40}; do
    [[ ! -s "$RECEIPT" ]] || break
    /bin/sleep 0.1
done
[[ -s "$RECEIPT" ]] || { printf 'error: fixture readiness receipt missing; no relaunch attempted\n' >&2; exit 1; }
PID="$(/usr/bin/plutil -extract processIdentifier raw -o - "$RECEIPT")"
ACTUAL_SESSION="$(/usr/bin/plutil -extract session raw -o - "$RECEIPT")"
[[ "$ACTUAL_SESSION" == "$SESSION" && "$PID" =~ ^[0-9]+$ ]] || exit 1
/bin/kill -0 "$PID" || exit 1
printf 'export BARLINE_FIXTURE_PID=%q\nexport BARLINE_FIXTURE_SESSION=%q\nexport BARLINE_FIXTURE_RECEIPT=%q\n' "$PID" "$SESSION" "$RECEIPT"
