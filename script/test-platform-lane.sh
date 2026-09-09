#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/lib/platform_lane.sh
source "$SCRIPT_DIR/lib/platform_lane.sh"

for version in 27.0 27.0.1 27.1; do
    barline_is_macos27_runtime "$version" || exit 1
done
for version in '' 26.6.2 28.0 270.0 27 27.beta '27.0 unknown'; do
    if barline_is_macos27_runtime "$version"; then
        printf 'Invalid runtime was accepted\n' >&2
        exit 1
    fi
done
for version in 'Xcode 27' 'Xcode 27.1' $'Xcode 27\nBuild version 18A1'; do
    barline_is_xcode27_toolchain "$version" || exit 1
done
for version in '' 'Xcode 26.6' 'Xcode 270' 'Xcode 27invalid' 'Xcode 28'; do
    if barline_is_xcode27_toolchain "$version"; then
        printf 'Invalid toolchain was accepted\n' >&2
        exit 1
    fi
done
printf 'OS lane classification: 18 positive/negative cases passed. No runtime support certified.\n'
