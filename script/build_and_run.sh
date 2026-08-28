#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Barline"
HELPER_NAME="BarlineMenuService"
BUNDLE_ID="com.mabryventures.Barline"
LOG_SUBSYSTEM="com.mabryventures.Barline"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/Barline.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.artifacts/run/DerivedData"
SOURCE_PACKAGES="$ROOT_DIR/.artifacts/run/SourcePackages"

CONFIGURATION="Debug"
MODE="run"
CLEAN=0
XCODE_PATH="/Applications/Xcode.app"

usage() {
    echo "usage: $0 [--clean] [--release] [--verify|--logs|--telemetry|--debug] [--xcode <path>]" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN=1
            ;;
        --release)
            CONFIGURATION="Release"
            ;;
        --verify)
            MODE="verify"
            ;;
        --logs)
            MODE="logs"
            ;;
        --telemetry)
            MODE="telemetry"
            ;;
        --debug)
            MODE="debug"
            ;;
        --xcode)
            shift
            if [[ $# -eq 0 ]]; then
                usage
                exit 2
            fi
            XCODE_PATH="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
    shift
done

if [[ "$XCODE_PATH" == *.app ]]; then
    DEVELOPER_PATH="$XCODE_PATH/Contents/Developer"
else
    DEVELOPER_PATH="$XCODE_PATH"
fi

if [[ ! -x "$DEVELOPER_PATH/usr/bin/xcodebuild" ]]; then
    echo "error: xcodebuild not found under $DEVELOPER_PATH" >&2
    exit 1
fi

export DEVELOPER_DIR="$DEVELOPER_PATH"

stop_processes() {
    /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    /usr/bin/pkill -x "$HELPER_NAME" >/dev/null 2>&1 || true
}

xcodebuild_base=(
    xcodebuild
    -project "$PROJECT"
    -scheme "$APP_NAME"
    -configuration "$CONFIGURATION"
    -destination "platform=macOS,arch=arm64"
    -derivedDataPath "$DERIVED_DATA"
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES"
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
)

stop_processes

if [[ $CLEAN -eq 1 ]]; then
    "${xcodebuild_base[@]}" clean
fi

"${xcodebuild_base[@]}" -quiet build

APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ ! -x "$APP_BINARY" ]]; then
    echo "error: expected built application at $APP_BUNDLE" >&2
    exit 1
fi

# File-provider metadata on the workspace is not valid code-signing input.
# Strip it from the derived product, then apply a local-only ad-hoc signature.
/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
    local actual_bundle_id
    local architecture

    actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
    if [[ "$actual_bundle_id" != "$BUNDLE_ID" ]]; then
        echo "error: expected bundle identifier $BUNDLE_ID, found $actual_bundle_id" >&2
        return 1
    fi

    architecture="$(/usr/bin/lipo -archs "$APP_BINARY")"
    if [[ "$architecture" != "arm64" ]]; then
        echo "error: expected arm64 application, found $architecture" >&2
        return 1
    fi

    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
    open_app

    for _ in {1..20}; do
        if /usr/bin/pgrep -x "$APP_NAME" >/dev/null; then
            echo "verified: $APP_NAME is running from $APP_BUNDLE"
            return 0
        fi
        sleep 0.25
    done

    echo "error: $APP_NAME did not remain running after launch" >&2
    return 1
}

case "$MODE" in
    run)
        open_app
        ;;
    verify)
        verify_app
        ;;
    logs)
        open_app
        exec /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\" OR process == \"$HELPER_NAME\""
        ;;
    telemetry)
        open_app
        exec /usr/bin/log stream --info --style compact --predicate "subsystem == \"$LOG_SUBSYSTEM\""
        ;;
    debug)
        exec /usr/bin/lldb -- "$APP_BINARY"
        ;;
esac
