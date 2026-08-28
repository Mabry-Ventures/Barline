#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=script/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

INSTALL_TOOLS=false
INSTALL_HOOKS=false
XCODE_PATH=""

usage() {
    cat <<'EOF'
Usage: ./script/bootstrap.sh [--install-tools] [--install-hooks] [--xcode PATH]

Verifies the local Apple Silicon build environment. Tool installation uses the
checked-in Brewfile and never changes the global Xcode selection.
EOF
}

while (($#)); do
    case "$1" in
        --install-tools) INSTALL_TOOLS=true ;;
        --install-hooks) INSTALL_HOOKS=true ;;
        --xcode)
            (($# >= 2)) || barline_die "--xcode requires a path"
            XCODE_PATH="$2"
            shift
            ;;
        --help|-h) usage; exit 0 ;;
        *) barline_die "unknown option: $1" ;;
    esac
    shift
done

ROOT="$(barline_repo_root)"
cd "$ROOT"

[[ "$(uname -s)" == Darwin ]] || barline_die "Barline bootstrap requires macOS"
[[ "$(uname -m)" == arm64 ]] || barline_die "Barline requires an Apple Silicon arm64 host"

printf 'Installed Xcodes:\n'
find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print | sort || true

DEVELOPER_PATH="$(barline_xcode_developer_dir "$XCODE_PATH")"
printf 'Production Xcode: %s\n' "$DEVELOPER_PATH"
DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild -version

if find /Applications -maxdepth 1 -type d \( -name 'Xcode*beta*.app' -o -name 'Xcode*27*.app' \) -print -quit | grep -q .; then
    printf 'Optional Xcode 27/beta candidate detected. Validate it explicitly with ./script/ci.sh xcode27 --xcode PATH.\n'
else
    printf 'Optional Xcode 27/beta not found; xcode27 validation remains unavailable.\n'
fi

if "$INSTALL_TOOLS"; then
    barline_require_command brew
    brew bundle --file "$ROOT/Brewfile"
else
    missing=()
    for tool in actionlint shellcheck swiftformat swiftlint; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    ((${#missing[@]} == 0)) || barline_die "missing tools: ${missing[*]}; rerun with --install-tools"
fi

if [[ ! -f Config/Local.xcconfig ]]; then
    cp Config/Local.example.xcconfig Config/Local.xcconfig
    printf 'Created ignored Config/Local.xcconfig from the example.\n'
fi

DEVELOPER_DIR="$DEVELOPER_PATH" xcodebuild -resolvePackageDependencies \
    -project Barline.xcodeproj -scheme Barline
swift package --package-path BarlineCore resolve

if "$INSTALL_HOOKS"; then
    git config core.hooksPath .githooks
    printf 'Configured repository-local hooks. Emergency bypass: git commit/push --no-verify (document why).\n'
fi

printf 'Bootstrap complete. Run ./script/ci.sh fast.\n'
