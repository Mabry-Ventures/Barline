#!/usr/bin/env ruby
# Structural regression gate. System discovery/invocation still needs signed UI evidence.
require 'json'
require 'open3'

module AppIntentsTopology
  module_function

  def require_value(condition, message)
    raise ArgumentError, message unless condition
  end

  def plist(path)
    output, _error, status = Open3.capture3('/usr/bin/plutil', '-convert', 'json', '-o', '-', path)
    require_value(status.success?, 'unreadable property list')
    JSON.parse(output)
  end

  def validate_attributes(info)
    require_value(!info.key?('NSExtension'), 'legacy NSExtension registration is forbidden')
    require_value(info.dig('EXAppExtensionAttributes', 'EXExtensionPointIdentifier') ==
      'com.apple.appintents-extension', 'App Intents ExtensionKit registration is missing')
  end

  def validate_source(project, info, source)
    validate_attributes(info)
    objects = project.fetch('objects')
    targets = objects.values.select { |v| v['isa'] == 'PBXNativeTarget' && v['name'] == 'BarlineIntents' }
    require_value(targets.length == 1, 'expected one intents target')
    target = targets.first
    require_value(target['productType'] == 'com.apple.product-type.extensionkit-extension',
      'intents target must use ExtensionKit product type')
    require_value(objects.dig(target['productReference'], 'explicitFileType') == 'wrapper.extensionkit-extension',
      'intents product reference must use ExtensionKit file type')
    require_value(source.match?(/@main\s+struct\s+BarlineIntentsExtension\s*:\s*AppIntentsExtension\s*\{/),
      'AppIntentsExtension entry point is missing')
    app = objects.values.find { |v| v['isa'] == 'PBXNativeTarget' && v['name'] == 'Barline' }
    require_value(!app.nil?, 'host target is missing')
    copies = app.fetch('buildPhases').map do |key|
      phase = objects.fetch(key)
      next unless phase['isa'] == 'PBXCopyFilesBuildPhase'
      next unless phase.fetch('files').any? { |file| objects.fetch(file)['fileRef'] == target['productReference'] }
      phase
    end.compact
    require_value(copies.length == 1, 'intents product must have exactly one host embed phase')
    require_value(copies.first['dstSubfolderSpec'].to_s == '16' &&
      copies.first['dstPath'] == '$(EXTENSIONS_FOLDER_PATH)', 'intents product must be embedded in Contents/Extensions')
    phases = target.fetch('buildPhases').map { |key| objects.fetch(key) }
    sources = phases.select { |v| v['isa'] == 'PBXSourcesBuildPhase' }.flat_map { |v| v.fetch('files') }
    require_value(sources.any? { |key| objects.dig(objects.fetch(key)['fileRef'], 'path') == 'BarlineIntents.swift' },
      'intents entry-point source is not a target member')
  end

  def validate_bundle(app)
    extension = File.join(app, 'Contents/Extensions/BarlineIntents.appex')
    require_value(File.directory?(extension), 'embedded ExtensionKit product is missing')
    require_value(!File.exist?(File.join(app, 'Contents/PlugIns/BarlineIntents.appex')),
      'stale legacy intents product is embedded')
    info = plist(File.join(extension, 'Contents/Info.plist'))
    validate_attributes(info)
    require_value(info['CFBundlePackageType'] == 'XPC!', 'intents product has wrong package type')
    executable = info.fetch('CFBundleExecutable')
    require_value(executable == File.basename(executable), 'invalid intents executable name')
    binary = File.join(extension, 'Contents/MacOS', executable)
    architectures, _error, status = Open3.capture3('/usr/bin/lipo', '-archs', binary)
    require_value(status.success? && architectures.strip == 'arm64', 'intents executable must be thin arm64')
    metadata = File.join(extension, 'Contents/Resources/Metadata.appintents/extract.actionsdata')
    require_value(File.file?(metadata) && File.size(metadata).positive?, 'intents metadata is missing')
    validate_metadata(JSON.parse(File.read(metadata)))
  end

  def validate_metadata(metadata)
    { 'actions' => %w[BarlineFocusFilter OpenBarlineIntent SwitchBarlineProfileIntent],
      'entities' => ['BarlineProfileEntity'], 'queries' => ['BarlineProfileQuery'] }.each do |kind, identifiers|
      values = metadata[kind]
      require_value(values.is_a?(Hash) && identifiers.all? { |key| values.key?(key) },
        "required intents #{kind} metadata is missing")
    end
    focus = metadata.fetch('actions').fetch('BarlineFocusFilter')
    require_value(focus.is_a?(Hash) && Array(focus['systemProtocols']).include?(
      'com.apple.link.systemProtocol.FocusConfiguration'), 'action does not declare the Focus Filter system protocol')
    parameters = focus['parameters']
    require_value(parameters.is_a?(Array), 'Focus Filter parameters are missing')
    profiles = parameters.select { |parameter| parameter.is_a?(Hash) && parameter['name'] == 'profile' }
    require_value(profiles.length == 1 && profiles.first['isOptional'] == true &&
      profiles.first.dig('valueType', 'entity', 'wrapper', 'typeName') == 'BarlineProfileEntity',
      'Focus Filter must expose one optional saved-layout entity')
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    if ARGV.length == 2 && ARGV.first == '--app'
      AppIntentsTopology.validate_bundle(ARGV.last)
    elsif ARGV.empty?
      root = File.expand_path('..', __dir__)
      AppIntentsTopology.validate_source(
        AppIntentsTopology.plist(File.join(root, 'Barline.xcodeproj/project.pbxproj')),
        AppIntentsTopology.plist(File.join(root, 'BarlineIntents/Info.plist')),
        File.read(File.join(root, 'BarlineIntents/BarlineIntents.swift'))
      )
    else
      raise ArgumentError, 'usage: validate-app-intents-topology.rb [--app APP]'
    end
    puts 'PASS: App Intents topology; not system runtime qualification'
  rescue ArgumentError, KeyError, JSON::ParserError => error
    warn "FAIL: #{error.message}"
    exit 1
  end
end
