#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS="${BARLINE_SOAK_ITERATIONS:-10}"

[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || {
    printf 'error: BARLINE_SOAK_ITERATIONS must be a positive integer\n' >&2
    exit 2
}

cd "$ROOT"
for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
    printf 'Soak iteration %d/%d\n' "$iteration" "$ITERATIONS"
    swift test --package-path BarlineCore \
        --filter 'BarlineCoreTests\.(StateCoordinatorTests|ProfileTests|DeterministicSearchIndexTests)/'
done

./script/test-xpc-interruption.sh
./script/test-performance-smoke.sh

printf 'PASS: %d state/profile/search cycles plus helper interruption and responsiveness probes completed\n' "$ITERATIONS"
