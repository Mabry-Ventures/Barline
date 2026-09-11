#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/lib/release-notes.sh
source "$SCRIPT_DIR/lib/release-notes.sh"

WORK="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/barline-release-notes.XXXXXX")"
trap '/bin/rm -rf "$WORK"' EXIT
cases=0

fail() {
    printf 'release notes: %s\n' "$*" >&2
    exit 1
}

pass() {
    cases=$((cases + 1))
}

cat >"$WORK/CHANGELOG.md" <<'MD'
# Changelog

## 2.0.11 (build 40) — September 11, 2026

- First change with a wrapped
  continuation line.

Build 39 passed its release gates but was not published.

- Second change — with an em dash.
- Third change directly after.

Before publication, build 40 must pass the complete gate.

## 2.0.1 (build 30) — candidate

- Older change for 2.0.1.

## Unreleased

- Unreleased change that must not appear.
MD

cat >"$WORK/expected-2.0.11.md" <<'MD'
## 2.0.11 (build 40) — September 11, 2026

- First change with a wrapped
  continuation line.

- Second change — with an em dash.
- Third change directly after.
MD

cat >"$WORK/expected-2.0.1.md" <<'MD'
## 2.0.1 (build 30) — candidate

- Older change for 2.0.1.
MD

barline_extract_release_notes "$WORK/CHANGELOG.md" 2.0.11 40 "$WORK/out.md" || fail "current section extraction failed"
cmp -s "$WORK/out.md" "$WORK/expected-2.0.11.md" || fail "current section output differs: $(diff "$WORK/expected-2.0.11.md" "$WORK/out.md" | head -5)"
pass

# The child shell must expand its own positional parameters, so the script is
# intentionally single-quoted.
# shellcheck disable=SC2016
env -i PATH=/usr/bin:/bin HOME="$HOME" /bin/bash -c \
    'source "$1"; barline_extract_release_notes "$2" 2.0.11 40 "$3"' _ \
    "$SCRIPT_DIR/lib/release-notes.sh" "$WORK/CHANGELOG.md" "$WORK/out-no-locale.md" ||
    fail "extraction failed without an inherited locale"
cmp -s "$WORK/out-no-locale.md" "$WORK/expected-2.0.11.md" || fail "output changed without an inherited locale"
pass

barline_extract_release_notes "$WORK/CHANGELOG.md" 2.0.1 30 "$WORK/out-older.md" || fail "older section extraction failed"
cmp -s "$WORK/out-older.md" "$WORK/expected-2.0.1.md" || fail "version prefix matched the wrong section"
pass

if barline_extract_release_notes "$WORK/CHANGELOG.md" 3.0.0 1 "$WORK/missing.md" 2>/dev/null; then
    fail "missing version was accepted"
fi
pass

if barline_extract_release_notes "$WORK/CHANGELOG.md" 2.0.11 41 "$WORK/mismatch.md" 2>/dev/null; then
    fail "mismatched build was accepted"
fi
pass

printf '# Changelog\n\n## 4.0.0 (build 1) — draft\n\nOnly a release-process paragraph.\n' >"$WORK/NO-ITEMS.md"
if barline_extract_release_notes "$WORK/NO-ITEMS.md" 4.0.0 1 "$WORK/no-items.md" 2>/dev/null; then
    fail "section without list items was accepted"
fi
pass

printf 'Release notes extraction: %d cases passed.\n' "$cases"
