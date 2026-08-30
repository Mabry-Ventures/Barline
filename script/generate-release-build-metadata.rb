#!/usr/bin/env ruby

require "json"

abort "usage: generate-release-build-metadata.rb RAW_SETTINGS OUTPUT SHA DISTRIBUTION" unless ARGV.length == 4

raw_settings_path, output_path, commit_sha, distribution = ARGV
abort "error: invalid release commit SHA" unless commit_sha.match?(/\A[0-9a-f]{40}\z/)
abort "error: invalid release distribution" unless %w[developer-id unsigned].include?(distribution)

settings = JSON.parse(File.read(raw_settings_path)).fetch(0).fetch("buildSettings")
required_setting = lambda do |name|
  value = settings.fetch(name, "")
  abort "error: required Release build setting is missing or unresolved: #{name}" if value.empty? || value.include?("$(")
  value
end

metadata = {
  commit_sha: commit_sha,
  configuration: "Release",
  architecture: "arm64",
  distribution: distribution,
  identifiers: {
    application: required_setting.call("BARLINE_APP_BUNDLE_IDENTIFIER"),
    menu_service: required_setting.call("BARLINE_MENU_SERVICE_BUNDLE_IDENTIFIER"),
    intents_extension: required_setting.call("BARLINE_INTENTS_BUNDLE_IDENTIFIER"),
    app_group: required_setting.call("BARLINE_APP_GROUP_IDENTIFIER")
  }
}

File.write(output_path, JSON.pretty_generate(metadata) + "\n")
