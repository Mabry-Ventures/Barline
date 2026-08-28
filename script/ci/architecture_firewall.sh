#!/usr/bin/env bash

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
failures=0

report_matches() {
    local title="$1"
    shift
    local output
    output="$("$@" || true)"
    if [[ -n "$output" ]]; then
        printf 'firewall: %s\n%s\n' "$title" "$output" >&2
        failures=$((failures + 1))
    fi
}

report_matches "direct private symbol declarations are forbidden; use DynamicSymbolResolver" \
    rg -n '@_silgen_name' --glob '*.swift' .

private_pattern='\b(CGS(MainConnectionID|CopyWindowsWithOptionsAndTags|CopyWindowProperty|SetWindowProperty|GetWindowOwner|GetWindowBounds|GetWindowLevel|GetActiveSpace|GetSpaceForWindow|GetWindowCount|GetWindowList|GetOnScreenWindowList|GetOnScreenWindowCount|IsWindowOnScreen|GetWindowTags|OrderWindow|SetWindowTags|ClearWindowTags)|GetProcessForPID)\b'
matches="$(rg -n "$private_pattern" --glob '*.swift' . || true)"
if [[ -n "$matches" ]]; then
    outside="$(printf '%s\n' "$matches" | grep -v '^\./BarlineMenuService/' || true)"
    if [[ -n "$outside" ]]; then
        printf 'firewall: private WindowServer symbol references escaped BarlineMenuService\n%s\n' "$outside" >&2
        failures=$((failures + 1))
    fi
fi

raw_ids="$(rg -n '\bCGWindowID\b' Barline BarlineCore --glob '*.swift' || true)"
if [[ -n "$raw_ids" ]]; then
    printf 'firewall: ephemeral CGWindowID leaked into app/core domain\n%s\n' "$raw_ids" >&2
    failures=$((failures + 1))
fi

if ! ruby -e '
  files = Dir.glob("{Barline,BarlineCore,BarlineMenuService,Shared}/**/*.swift")
  bad = []
  files.each do |path|
    lines = File.readlines(path)
    lines.each_with_index do |line, index|
      next unless line.match?(/while\s+true|for\s+await\s+.*Timer|repeats:\s*true|schedule\([^\n]*repeating:/)
      window = lines[index, 20].join
      bad << "#{path}:#{index + 1}:#{line.strip}" if line.include?("repeats: true") || line.include?("repeating:") || window.match?(/Task\.sleep|Thread\.sleep|usleep/)
    end
  end
  if bad.any?
    warn "polling: recurring timer or sleep loop requires an event-driven replacement or a documented bounded exception"
    warn bad.join("\n")
    exit 1
  end
'; then
    failures=$((failures + 1))
fi

if ((failures)); then
    printf 'architecture firewall failed with %d category violation(s)\n' "$failures" >&2
    exit 1
fi

printf 'Architecture firewall passed: private symbols are service-isolated and no frequent polling pattern was found.\n'
