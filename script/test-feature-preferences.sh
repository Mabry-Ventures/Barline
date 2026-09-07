#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT/.artifacts/workstreams/feature-preferences"
mkdir -p "$ARTIFACT_DIR"
swift build --package-path "$ROOT/BarlineCore" --scratch-path "$ARTIFACT_DIR" \
    > "$ARTIFACT_DIR/build.log" 2>&1
BIN_PATH="$(swift build --package-path "$ROOT/BarlineCore" --scratch-path "$ARTIFACT_DIR" --show-bin-path)"
core_objects=("$BIN_PATH"/BarlineCore.build/*.swift.o)
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -parse-as-library -I "$BIN_PATH/Modules" \
    "$ROOT/Barline/Profiles/ContextualRuleStore.swift" \
    "$ROOT/Barline/Hotkeys/ItemShortcutPreferences.swift" \
    "$ROOT/script/tests/FeaturePreferencesProbe.swift" \
    "${core_objects[@]}" -o "$ARTIFACT_DIR/feature-preferences-probe"
TEST_DIR="$(mktemp -d "$ARTIFACT_DIR/data.XXXXXX")"
"$ARTIFACT_DIR/feature-preferences-probe" "$TEST_DIR" \
    2>&1 | tee "$ARTIFACT_DIR/result.txt"
