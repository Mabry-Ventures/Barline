#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_PATH="${DEVELOPER_DIR:-$(xcode-select -p)}"
RESULT_ROOT="$ROOT/.artifacts/xcode-ui"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/barline-xcode-ui.XXXXXX")"

cleanup() {
    /usr/bin/pkill -x BarlineFixture >/dev/null 2>&1 || true
    /bin/rm -rf "$DERIVED_DATA"
}
trap cleanup EXIT

if ! /usr/sbin/DevToolsSecurity -status 2>&1 | /usr/bin/grep -qi 'enabled'; then
    printf 'BLOCKED: XCUITest execution requires Developer Tools automation mode. Enabling it requires administrator authorization.\n' >&2
    exit 2
fi

mkdir -p "$RESULT_ROOT"

common=(
    env DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild
    -project "$ROOT/Barline.xcodeproj"
    -scheme Barline
    -testPlan Barline
    -configuration Debug
    -destination 'platform=macOS,arch=arm64'
    -derivedDataPath "$DERIVED_DATA"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    ENABLE_HARDENED_RUNTIME=NO
    ENABLE_APP_SANDBOX=NO
)

"${common[@]}" build-for-testing
result_bundle="$RESULT_ROOT/BarlineUITests.xcresult"
[[ ! -e "$result_bundle" ]] || /bin/rm -rf "$result_bundle"
"${common[@]}" -resultBundlePath "$result_bundle" \
    -only-testing:BarlineUITests test-without-building

printf 'PASS: BarlineUITests executed through the fixture application\n'
