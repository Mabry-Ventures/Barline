#!/usr/bin/env bash

set -euo pipefail

# Gate scripts read repository files with Ruby's File.read/readlines and then
# match against them. Ruby derives its default external encoding from the
# locale, so an unset or C locale makes every one of those reads US-ASCII and
# raises ArgumentError on the first byte above 127. Several tracked files carry
# non-ASCII text (an arrow in the issue template, symbols in KeyCode.swift), so
# the crash is guaranteed rather than incidental, and it surfaces as a bogus
# gate failure rather than as an encoding error. Pin UTF-8 for every child
# process instead of guarding each ruby invocation.
#
# This overrides the caller's locale rather than defaulting to it: an inherited
# LC_ALL=C or LC_CTYPE=C is precisely the condition that breaks the scanners, so
# honouring it would leave the gate broken in the case worth defending against.
# Gate results must not depend on the locale of whichever shell invoked them.
#
# Hardcoding en_US.UTF-8 is not portable: the repository-hygiene lane runs on
# Linux, where a minimal image commonly provides C.UTF-8 and no en_US.UTF-8.
# Exporting a locale the host lacks silently leaves Ruby at US-ASCII, so probe
# for one that exists, and set RUBYOPT as well. RUBYOPT fixes Ruby's external
# encoding directly, independently of any locale, and is inherited by nested
# child processes.
# Capture the locale list rather than piping it into `grep -q`: under
# `set -o pipefail`, grep exits at the first match and the SIGPIPE it delivers
# makes the whole pipeline report failure, so the probe would never fire.
barline_available_locales="$(locale -a 2>/dev/null || true)"
for barline_utf8_locale in en_US.UTF-8 C.UTF-8; do
    if printf '%s\n' "$barline_available_locales" | grep -qix "$barline_utf8_locale"; then
        export LANG="$barline_utf8_locale"
        export LC_ALL="$barline_utf8_locale"
        break
    fi
done
unset barline_utf8_locale barline_available_locales
export RUBYOPT="${RUBYOPT:+$RUBYOPT }-EUTF-8"

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
