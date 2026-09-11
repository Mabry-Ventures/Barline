#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/lib/arm64-bundle.sh
source "$SCRIPT_DIR/lib/arm64-bundle.sh"

command -v xcrun >/dev/null 2>&1 || { printf 'arm64 bundle: xcrun is required\n' >&2; exit 1; }
WORK="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/barline-arm64-bundle.XXXXXX")"
trap '/bin/rm -rf "$WORK"' EXIT
cases=0

fail() {
    printf 'arm64 bundle: %s\n' "$*" >&2
    exit 1
}

pass() {
    cases=$((cases + 1))
}

printf 'int main(void) { return 0; }\n' >"$WORK/main.c"
printf 'int barline_fixture(void) { return 1; }\n' >"$WORK/lib.c"

APP="$WORK/Fixture.app"
FRAMEWORK="$APP/Contents/Frameworks/Fixture.framework"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$FRAMEWORK/Versions/A"
xcrun clang -arch arm64 -arch x86_64 -o "$APP/Contents/MacOS/Fixture" "$WORK/main.c"
xcrun clang -arch arm64 -o "$APP/Contents/MacOS/thin" "$WORK/main.c"
xcrun clang -arch arm64 -arch x86_64 -dynamiclib -install_name @rpath/Fixture.framework/Fixture \
    -o "$FRAMEWORK/Versions/A/Fixture" "$WORK/lib.c"
ln -s A "$FRAMEWORK/Versions/Current"
ln -s Versions/Current/Fixture "$FRAMEWORK/Fixture"
printf 'not a binary\n' >"$APP/Contents/Resources/notes.txt"
chmod 755 "$APP/Contents/MacOS/Fixture"
thin_before="$(/usr/bin/shasum -a 256 "$APP/Contents/MacOS/thin" | awk '{print $1}')"
notes_before="$(/usr/bin/shasum -a 256 "$APP/Contents/Resources/notes.txt" | awk '{print $1}')"

if barline_require_apple_silicon_bundle "$APP" >/dev/null 2>&1; then
    fail "universal bundle passed validation before thinning"
fi
pass

barline_thin_bundle_to_apple_silicon "$APP" >/dev/null || fail "thinning failed"
[[ "$(/usr/bin/lipo -archs "$APP/Contents/MacOS/Fixture")" == arm64 ]] || fail "executable still universal"
pass
[[ "$(/usr/bin/lipo -archs "$FRAMEWORK/Versions/A/Fixture")" == arm64 ]] || fail "framework dylib still universal"
pass
[[ "$(/usr/bin/stat -f %Lp "$APP/Contents/MacOS/Fixture")" == 755 ]] || fail "executable mode changed"
pass
[[ "$(/usr/bin/shasum -a 256 "$APP/Contents/MacOS/thin" | awk '{print $1}')" == "$thin_before" ]] || fail "arm64-only binary was rewritten"
pass
[[ "$(/usr/bin/shasum -a 256 "$APP/Contents/Resources/notes.txt" | awk '{print $1}')" == "$notes_before" ]] || fail "non-Mach-O file changed"
pass
[[ -L "$FRAMEWORK/Versions/Current" && -L "$FRAMEWORK/Fixture" ]] || fail "framework symlinks were replaced"
pass
"$APP/Contents/MacOS/Fixture" || fail "thinned executable does not run"
pass

report="$(barline_require_apple_silicon_bundle "$APP")" || fail "thinned bundle failed validation"
[[ "$report" == "Apple Silicon only: 3 Mach-O files verified" ]] || fail "unexpected validation report: $report"
pass

INTEL="$WORK/Intel.app"
mkdir -p "$INTEL/Contents/MacOS"
xcrun clang -arch x86_64 -o "$INTEL/Contents/MacOS/Intel" "$WORK/main.c"
if barline_thin_bundle_to_apple_silicon "$INTEL" >/dev/null 2>&1; then
    fail "x86_64-only binary was accepted"
fi
pass

EMPTY="$WORK/Empty.app"
mkdir -p "$EMPTY/Contents/Resources"
printf 'text\n' >"$EMPTY/Contents/Resources/readme.txt"
if barline_require_apple_silicon_bundle "$EMPTY" >/dev/null 2>&1; then
    fail "bundle without Mach-O files passed validation"
fi
pass

ARM64E="$WORK/Arm64e.app"
mkdir -p "$ARM64E/Contents/MacOS"
if xcrun clang -arch arm64e -arch x86_64 -o "$ARM64E/Contents/MacOS/Arm64e" "$WORK/main.c" >/dev/null 2>&1; then
    barline_thin_bundle_to_apple_silicon "$ARM64E" >/dev/null || fail "arm64e thinning failed"
    [[ "$(/usr/bin/lipo -archs "$ARM64E/Contents/MacOS/Arm64e")" == arm64e ]] || fail "arm64e slice not preserved"
    pass
fi

printf 'Apple Silicon bundle thinning: %d cases passed.\n' "$cases"
