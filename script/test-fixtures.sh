#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tests="$(swift test --package-path BarlineCore list)"
fixture_count="$(printf '%s\n' "$tests" | grep -Ec '^BarlineCoreTests\.(SnapshotValidationTests|StateCoordinatorTests|ProfileTests|MenuBarCommandValidationTests)/')"
if ((fixture_count < 20)); then
    printf 'error: expected at least 20 fixture/state regression cases, found %d\n' "$fixture_count" >&2
    exit 1
fi

swift test --package-path BarlineCore \
    --filter 'BarlineCoreTests\.(SnapshotValidationTests|StateCoordinatorTests|ProfileTests|MenuBarCommandValidationTests)/'

printf 'PASS: %d fixture/state regression cases were discovered and executed\n' "$fixture_count"
