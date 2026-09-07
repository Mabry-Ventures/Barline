#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT/.artifacts/workstreams/search-build"
mkdir -p "$ARTIFACT_DIR"

# Compile the actual actor against BarlineCore, without AppKit or app launch.
swift build --package-path "$ROOT/BarlineCore" --scratch-path "$ARTIFACT_DIR" \
    2>&1 | tee "$ARTIFACT_DIR/preferences-build.log"
BIN_PATH="$(swift build --package-path "$ROOT/BarlineCore" --scratch-path "$ARTIFACT_DIR" --show-bin-path)"
core_objects=("$BIN_PATH"/BarlineCore.build/*.swift.o)
if [[ ! -e "${core_objects[0]}" ]]; then
    printf 'error: BarlineCore object files are unavailable for search preferences probe\n' >&2
    exit 1
fi
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -parse-as-library -I "$BIN_PATH/Modules" \
    "$ROOT/Barline/MenuBar/Search/SearchItemPreferences.swift" \
    "$ROOT/script/tests/SearchItemPreferencesProbe.swift" \
    "${core_objects[@]}" -o "$ARTIFACT_DIR/search-preferences-probe"
TEST_DIR="$(mktemp -d "$ARTIFACT_DIR/preferences-data.XXXXXX")"
"$ARTIFACT_DIR/search-preferences-probe" "$TEST_DIR" \
    2>&1 | tee "$ARTIFACT_DIR/preferences-result.txt"
