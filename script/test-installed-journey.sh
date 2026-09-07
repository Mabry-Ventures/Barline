#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${BARLINE_CANDIDATE_APP:?Set the absolute path to the already-running signed candidate}"
: "${BARLINE_SOURCE_SHA:?Set the candidate source SHA}"
: "${BARLINE_EXPECTED_PID:?Set the exact candidate PID}"
: "${BARLINE_FIXTURE_PID:?Set the exact journey fixture PID}"
: "${BARLINE_FIXTURE_RECEIPT:?Set the fixture receipt path}"
: "${BARLINE_FIXTURE_SESSION:?Set the per-run fixture session token}"
[[ "$BARLINE_SOURCE_SHA" =~ ^[a-f0-9]{40}$ ]] || { printf 'error: invalid source SHA\n' >&2; exit 2; }
[[ "$BARLINE_CANDIDATE_APP" == /* && -d "$BARLINE_CANDIDATE_APP" ]] || exit 2
/usr/bin/codesign --verify --deep --strict "$BARLINE_CANDIDATE_APP"
/usr/sbin/spctl --assess --type execute "$BARLINE_CANDIDATE_APP"
/usr/bin/xcrun stapler validate "$BARLINE_CANDIDATE_APP"
RELEASE_DIR="${BARLINE_RELEASE_DIR:-$ROOT/.artifacts/release/$BARLINE_SOURCE_SHA}"
METADATA="$RELEASE_DIR/build-metadata.json"
[[ -f "$METADATA" ]] || { printf 'error: candidate source metadata missing\n' >&2; exit 1; }
ACTUAL_SHA="$(/usr/bin/plutil -extract commit_sha raw -o - "$METADATA")"
[[ "$ACTUAL_SHA" == "$BARLINE_SOURCE_SHA" ]] || { printf 'error: candidate source mismatch\n' >&2; exit 1; }
export BARLINE_APP_BUNDLE_IDENTIFIER
BARLINE_APP_BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BARLINE_CANDIDATE_APP/Contents/Info.plist")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$BARLINE_CANDIDATE_APP/Contents/Info.plist")"
export BARLINE_EXECUTABLE_SHA256
BARLINE_EXECUTABLE_SHA256="$(/usr/bin/shasum -a 256 "$BARLINE_CANDIDATE_APP/Contents/MacOS/$EXECUTABLE" | /usr/bin/awk '{print $1}')"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BARLINE_CANDIDATE_APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
RELEASE_ZIP="$RELEASE_DIR/dist/Barline-$VERSION.zip"
[[ -f "$RELEASE_ZIP" ]] || { printf 'error: source-bound release ZIP missing\n' >&2; exit 1; }
PACKAGED_SHA="$(/usr/bin/unzip -p "$RELEASE_ZIP" "Barline.app/Contents/MacOS/$EXECUTABLE" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
[[ "$PACKAGED_SHA" == "$BARLINE_EXECUTABLE_SHA256" ]] || { printf 'error: installed executable differs from source-bound release\n' >&2; exit 1; }
TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/barline-journey.XXXXXX")"
trap '/bin/rm -f "$TASK_DIR/probe"; /bin/rmdir "$TASK_DIR"' EXIT
xcrun swiftc -framework AppKit -framework CoreGraphics "$ROOT/script/test-installed-journey.swift" -o "$TASK_DIR/probe"
"$TASK_DIR/probe"
