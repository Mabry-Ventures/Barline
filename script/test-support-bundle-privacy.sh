#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
MODULE_CACHE="${TMPDIR:-/tmp}/barline-support-privacy-module-cache"
BINARY="${TMPDIR:-/tmp}/barline-support-privacy-tests"

if ! rg -q '(SupportBundle|DiagnosticBundle)' "$ROOT/Barline" --glob '*.swift'; then
    printf 'error: no Barline support-bundle exporter exists; bundle privacy cannot be runtime-verified\n' >&2
    failures=$((failures + 1))
fi

if ruby -e '
  patterns = /NSHomeDirectory|homeDirectoryForCurrentUser|NSUserName|userName|ProcessInfo\.processInfo\.(arguments|environment)|NSWorkspace\.shared\.runningApplications/
  findings = []
  Dir.glob("Barline/**/*.swift").each do |path|
    lines = File.readlines(path)
    lines.each_with_index do |line, index|
      next unless line.match?(/logger\.(debug|info|notice|warning|error|fault)|Logger\.[A-Za-z]+\.(debug|info|notice|warning|error|fault)/)
      statement = ""
      balance = 0
      lines[index, 12].each do |part|
        statement << part
        balance += part.count("(") - part.count(")")
        break if balance <= 0
      end
      findings << "#{path}:#{index + 1}" if statement.match?(patterns)
    end
  end
  if findings.any?
    warn "sensitive host/process data is reachable from a logging statement: #{findings.join(", ")}"
    exit 1
  end
'; then
    :
else
    failures=$((failures + 1))
fi

if git -C "$ROOT" grep -n -E -- '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}'; then
    printf 'error: credential-like content is tracked and could leak into diagnostics\n' >&2
    failures=$((failures + 1))
fi

if ((failures == 0)); then
    swift build --package-path "$ROOT/BarlineCore"
    BIN_PATH="$(swift build --package-path "$ROOT/BarlineCore" --show-bin-path)"
    core_objects=("$BIN_PATH"/BarlineCore.build/*.swift.o)
    if [[ ! -e "${core_objects[0]}" ]]; then
        printf 'error: BarlineCore object files are unavailable for privacy harness\n' >&2
        failures=$((failures + 1))
    else
        mkdir -p "$MODULE_CACHE"
        if ! xcrun swiftc \
            -module-cache-path "$MODULE_CACHE" \
            -I "$BIN_PATH/Modules" \
            "$ROOT/Barline/Platform/Diagnostics/SupportBundleExporter.swift" \
            "$ROOT/script/test-support-bundle-privacy.swift" \
            "${core_objects[@]}" \
            -o "$BINARY"; then
            failures=$((failures + 1))
        elif ! "$BINARY"; then
            failures=$((failures + 1))
        fi
    fi
fi

if ((failures)); then
    printf 'support-bundle privacy gate failed with %d finding(s)\n' "$failures" >&2
    exit 1
fi

printf 'PASS: support-bundle exporter exists and logging/source credential privacy checks passed\n'
