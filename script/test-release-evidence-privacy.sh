#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/barline-release-privacy.XXXXXX")"
trap '/bin/rm -rf -- "$SCRATCH"' EXIT

RAW_SETTINGS="$SCRATCH/raw-settings.json"
METADATA="$SCRATCH/build-metadata.json"
cat > "$RAW_SETTINGS" <<'JSON'
[
  {
    "buildSettings": {
      "BARLINE_APP_BUNDLE_IDENTIFIER": "com.example.Barline",
      "BARLINE_MENU_SERVICE_BUNDLE_IDENTIFIER": "com.example.Barline.MenuService",
      "BARLINE_INTENTS_BUNDLE_IDENTIFIER": "com.example.Barline.Intents",
      "BARLINE_APP_GROUP_IDENTIFIER": "group.com.example.Barline",
      "BARLINE_DEVELOPMENT_TEAM": "SENSITIVE-TEAM-CANARY",
      "BARLINE_APP_PROVISIONING_PROFILE_SPECIFIER": "SENSITIVE-PROFILE-CANARY",
      "BARLINE_DEVELOPER_ID_CERTIFICATE_SHA1": "SENSITIVE-CERTIFICATE-CANARY",
      "HOME": "/Users/sensitive-user-canary",
      "PATH": "/sensitive/path/canary",
      "USER": "sensitive-user-canary"
    }
  }
]
JSON

/usr/bin/ruby "$ROOT/script/generate-release-build-metadata.rb" \
    "$RAW_SETTINGS" "$METADATA" 0123456789abcdef0123456789abcdef01234567 developer-id

/usr/bin/ruby -rjson -e '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  expected = {
    "commit_sha" => "0123456789abcdef0123456789abcdef01234567",
    "configuration" => "Release",
    "architecture" => "arm64",
    "distribution" => "developer-id",
    "identifiers" => {
      "application" => "com.example.Barline",
      "menu_service" => "com.example.Barline.MenuService",
      "intents_extension" => "com.example.Barline.Intents",
      "app_group" => "group.com.example.Barline"
    }
  }
  abort "sanitized release metadata changed shape" unless document == expected
  serialized = JSON.generate(document)
  abort "release metadata leaked a sensitive canary" if serialized.match?(/SENSITIVE|sensitive-user|sensitive\/path/i)
' "$METADATA"

# The dollar-prefixed strings below are literal release-script source invariants.
# shellcheck disable=SC2016
/usr/bin/ruby -e '
  source = File.read(ARGV.fetch(0))
  normalized = source.gsub(/\\\n[[:space:]]*/, " ")
  allowed_raw_uses = {
    "initialization" => /\ARAW_BUILD_SETTINGS_JSON=""\z/,
    "cleanup" => /\A    \[\[ -z "\$RAW_BUILD_SETTINGS_JSON" \]\] \|\| \/bin\/rm -f -- "\$RAW_BUILD_SETTINGS_JSON"\z/,
    "temporary allocation" => /\ARAW_BUILD_SETTINGS_JSON="\$\(mktemp "\$\{TMPDIR:-\/tmp\}\/barline-build-settings\.\$\{SHA\}\.XXXXXX"\)"\z/,
    "Xcode capture" => /\Aenv DEVELOPER_DIR="\$DEVELOPER_PATH" xcodebuild .* -showBuildSettings -json > "\$RAW_BUILD_SETTINGS_JSON"\z/,
    "setting lookup" => /\A    \/usr\/bin\/ruby -rjson -e .* "\$RAW_BUILD_SETTINGS_JSON" "\$1"\z/,
    "sanitized metadata producer" => /\A\/usr\/bin\/ruby "\$ROOT\/script\/generate-release-build-metadata\.rb"  "\$RAW_BUILD_SETTINGS_JSON" "\$RELEASE_ROOT\/build-metadata\.json" "\$SHA" "\$DISTRIBUTION"\z/
  }
  raw_uses = normalized.lines.each_with_object([]) do |line, uses|
    stripped = line.chomp
    uses << stripped if stripped.include?("RAW_BUILD_SETTINGS_JSON")
  end
  abort "release script raw-settings data flow changed" unless raw_uses.length == allowed_raw_uses.length
  allowed_raw_uses.each do |label, pattern|
    matches = raw_uses.count { |line| line.match?(pattern) }
    abort "release script must have exactly one #{label} raw-settings use" unless matches == 1
  end
  raw_uses.each do |line|
    matches = allowed_raw_uses.values.count { |pattern| line.match?(pattern) }
    abort "release script has an unauthorized raw-settings use: #{line}" unless matches == 1
  end

  show_settings_calls = normalized.lines.grep(/-showBuildSettings/)
  abort "release script must have one build-settings producer" unless show_settings_calls.length == 1
  producer = %r{/usr/bin/ruby "\$ROOT/script/generate-release-build-metadata\.rb"[[:space:]]+"\$RAW_BUILD_SETTINGS_JSON"[[:space:]]+"\$RELEASE_ROOT/build-metadata\.json"[[:space:]]+"\$SHA"[[:space:]]+"\$DISTRIBUTION"}
  abort "release script bypasses the sanitized metadata producer" unless normalized.match?(producer)
' "$ROOT/script/release.sh"

printf 'PASS: release evidence preserves only canary-tested sanitized build metadata\n'
