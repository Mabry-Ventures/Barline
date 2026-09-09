#!/usr/bin/env bash

# Source only. Bind interactive evidence to one running, signed packaged app.
barline_verify_installed_candidate() {
    : "${BARLINE_CANDIDATE_APP:?Set the installed candidate app path}"
    : "${BARLINE_SOURCE_SHA:?Set the candidate source SHA}"
    [[ "$BARLINE_SOURCE_SHA" =~ ^[a-f0-9]{40}$ && "$BARLINE_CANDIDATE_APP" == /* ]] || return 2
    [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$BARLINE_SOURCE_SHA" ]] || return 1
    [[ -z "$(git -C "$ROOT" status --porcelain=v1)" ]] || return 1
    local candidate_pid executable version release_dir packaged_sha actual_path
    candidate_pid="$(pgrep -x Barline)"
    [[ "$candidate_pid" =~ ^[0-9]+$ ]] || return 1
    [[ -z "${BARLINE_EXPECTED_PID:-}" || "$candidate_pid" == "$BARLINE_EXPECTED_PID" ]] || return 1
    executable="$(plutil -extract CFBundleExecutable raw "$BARLINE_CANDIDATE_APP/Contents/Info.plist")"
    [[ "$executable" == Barline ]] || return 1
    actual_path="$(ps -p "$candidate_pid" -o comm=)"
    [[ "$actual_path" == "$BARLINE_CANDIDATE_APP/Contents/MacOS/$executable" ]] || return 1
    version="$(plutil -extract CFBundleShortVersionString raw "$BARLINE_CANDIDATE_APP/Contents/Info.plist")"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    release_dir="${BARLINE_RELEASE_DIR:-$ROOT/.artifacts/release/$BARLINE_SOURCE_SHA}"
    [[ "$(plutil -extract commit_sha raw "$release_dir/build-metadata.json")" == "$BARLINE_SOURCE_SHA" ]] || return 1
    BARLINE_EXECUTABLE_SHA256="$(shasum -a 256 "$BARLINE_CANDIDATE_APP/Contents/MacOS/$executable" | awk '{print $1}')"
    packaged_sha="$(unzip -p "$release_dir/dist/Barline-$version.zip" "Barline.app/Contents/MacOS/$executable" | shasum -a 256 | awk '{print $1}')"
    [[ "$packaged_sha" == "$BARLINE_EXECUTABLE_SHA256" ]] || return 1
    codesign --verify --deep --strict "$BARLINE_CANDIDATE_APP" || return 1
    BARLINE_EXPECTED_PID="$candidate_pid"
    BARLINE_APP_BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw "$BARLINE_CANDIDATE_APP/Contents/Info.plist")"
    export BARLINE_EXECUTABLE_SHA256 BARLINE_EXPECTED_PID BARLINE_APP_BUNDLE_IDENTIFIER
}
