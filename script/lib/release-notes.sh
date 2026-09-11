#!/usr/bin/env bash

# Source only. Sparkle shows the embedded notes in its update dialog, so release
# packaging publishes only the list items from the CHANGELOG section for the
# exact version and build being released. Standalone paragraphs in that section
# record release process rather than user-facing changes and are omitted.

barline_extract_release_notes() {
    local changelog="$1" version="$2" build="$3" output="$4"
    LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 /usr/bin/ruby -E UTF-8:UTF-8 -e '
        changelog, version, build, output = ARGV
        lines = File.readlines(changelog, chomp: true)
        start = lines.index { |line| line.start_with?("## #{version} ") }
        abort "error: CHANGELOG has no section for #{version}" unless start
        heading = lines[start]
        unless heading.start_with?("## #{version} (build #{build})")
            abort "error: CHANGELOG section for #{version} does not name build #{build}"
        end
        stop = ((start + 1)...lines.size).find { |index| lines[index].start_with?("## ") } || lines.size
        kept = []
        in_item = false
        lines[(start + 1)...stop].each do |line|
            if line.start_with?("- ")
                in_item = true
                kept << line
            elsif in_item && line.start_with?("  ") && !line.strip.empty?
                kept << line
            else
                in_item = false
                kept << "" if line.strip.empty? && !kept.empty? && !kept.last.empty?
            end
        end
        kept.pop while kept.last == ""
        if kept.none? { |line| line.start_with?("- ") }
            abort "error: CHANGELOG section for #{version} has no list items"
        end
        File.write(output, ([heading, ""] + kept).join("\n") + "\n")
    ' "$changelog" "$version" "$build" "$output"
}
