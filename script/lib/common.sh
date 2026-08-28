#!/usr/bin/env bash

set -euo pipefail

barline_die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

barline_require_command() {
    command -v "$1" >/dev/null 2>&1 || barline_die "missing required command '$1'; run ./script/bootstrap.sh"
}

barline_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || barline_die "run this command inside the Barline repository"
}

barline_xcode_developer_dir() {
    local requested="${1:-}"
    if [[ -n "$requested" ]]; then
        if [[ "$requested" == *.app ]]; then
            requested="${requested}/Contents/Developer"
        fi
        [[ -x "${requested}/usr/bin/xcodebuild" ]] || barline_die "no xcodebuild at ${requested}"
        printf '%s\n' "$requested"
        return
    fi
    xcode-select -p
}
