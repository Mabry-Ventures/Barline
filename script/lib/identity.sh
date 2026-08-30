#!/usr/bin/env bash

barline_validate_bundle_identifier() {
    local value="$1"
    local unresolved_marker="\$("
    [[ -n "$value" && "$value" != *"$unresolved_marker"* ]] || return 1
    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || return 1
    [[ "$value" == *.* && "$value" != *..* && "$value" != */* ]] || return 1
}

barline_resolve_identifier_build_setting() {
    local root="$1"
    local configuration="$2"
    local setting_name="$3"
    local settings_json identifier
    settings_json="$(mktemp "${TMPDIR:-/tmp}/barline-build-settings.XXXXXX")"
    if ! env DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}" xcodebuild \
        -project "$root/Barline.xcodeproj" -scheme Barline \
        -configuration "$configuration" -showBuildSettings -json > "$settings_json"
    then
        /bin/rm -f "$settings_json"
        return 1
    fi
    identifier="$(ruby -rjson -e '
      records = JSON.parse(File.read(ARGV.fetch(0))).select do |record|
        settings = record.fetch("buildSettings")
        record["target"] == "Barline" &&
          settings["PRODUCT_TYPE"] == "com.apple.product-type.application"
      end
      abort "expected one Barline application build-settings record" unless records.length == 1
      puts records.fetch(0).fetch("buildSettings").fetch(ARGV.fetch(1), "")
    ' "$settings_json" "$setting_name")"
    /bin/rm -f "$settings_json"
    barline_validate_bundle_identifier "$identifier" || {
        printf 'error: %s is missing, unresolved, or invalid\n' "$setting_name" >&2
        return 1
    }
    printf '%s\n' "$identifier"
}

barline_resolve_app_bundle_identifier() {
    barline_resolve_identifier_build_setting "$1" "$2" BARLINE_APP_BUNDLE_IDENTIFIER
}

barline_resolve_logging_subsystem() {
    barline_resolve_identifier_build_setting "$1" "$2" BARLINE_LOGGING_SUBSYSTEM
}
