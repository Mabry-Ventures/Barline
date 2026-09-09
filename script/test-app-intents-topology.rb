#!/usr/bin/env ruby
require_relative 'validate-app-intents-topology'

base = { 'objects' => {
  'product' => { 'explicitFileType' => 'wrapper.extensionkit-extension' },
  'host' => { 'isa' => 'PBXNativeTarget', 'name' => 'Barline', 'buildPhases' => ['copy'] },
  'intents' => { 'isa' => 'PBXNativeTarget', 'name' => 'BarlineIntents',
    'productType' => 'com.apple.product-type.extensionkit-extension', 'productReference' => 'product',
    'buildPhases' => ['sources'] },
  'copy' => { 'isa' => 'PBXCopyFilesBuildPhase', 'files' => ['embed'],
    'dstSubfolderSpec' => '16', 'dstPath' => '$(EXTENSIONS_FOLDER_PATH)' },
  'embed' => { 'fileRef' => 'product' },
  'sources' => { 'isa' => 'PBXSourcesBuildPhase', 'files' => ['sourceBuild'] },
  'sourceBuild' => { 'fileRef' => 'source' },
  'source' => { 'path' => 'BarlineIntents.swift' }
} }
info = { 'EXAppExtensionAttributes' => { 'EXExtensionPointIdentifier' => 'com.apple.appintents-extension' } }
source = '@main struct BarlineIntentsExtension: AppIntentsExtension {}'
AppIntentsTopology.validate_source(base, info, source)
mutations = [
  ->(p, _i, _s) { p['objects']['product']['explicitFileType'] = 'wrapper.app-extension' },
  ->(p, _i, _s) { p['objects']['intents']['productType'] = 'com.apple.product-type.app-extension' },
  ->(_p, i, _s) { i['NSExtension'] = {} },
  ->(_p, i, _s) { i['EXAppExtensionAttributes']['EXExtensionPointIdentifier'] = 'com.apple.appintents-service' },
  ->(_p, i, _s) { i.clear },
  ->(_p, _i, s) { s.replace('struct BarlineIntentsExtension: AppIntentsExtension {}') },
  ->(p, _i, _s) { p['objects']['copy']['dstPath'] = '' },
  ->(p, _i, _s) { p['objects']['copy']['dstSubfolderSpec'] = '13' },
  ->(p, _i, _s) { p['objects']['host']['buildPhases'] = [] },
  ->(p, _i, _s) { p['objects']['host']['buildPhases'] = ['copy', 'copy'] },
  ->(p, _i, _s) { p['objects']['sources']['files'] = [] },
  ->(p, _i, _s) { p['objects']['duplicate'] = p['objects']['intents'].dup }
]
mutations.each do |mutate|
  project_copy, info_copy, source_copy = Marshal.load(Marshal.dump([base, info, source]))
  mutate.call(project_copy, info_copy, source_copy)
  rejected = false
  begin
    AppIntentsTopology.validate_source(project_copy, info_copy, source_copy)
  rescue ArgumentError
    rejected = true
  end
  raise 'invalid topology was accepted' unless rejected
end
metadata = { 'actions' => %w[BarlineFocusFilter OpenBarlineIntent SwitchBarlineProfileIntent].to_h { |k| [k, {}] },
  'entities' => { 'BarlineProfileEntity' => {} }, 'queries' => { 'BarlineProfileQuery' => {} } }
metadata['actions']['BarlineFocusFilter'] = {
  'systemProtocols' => ['com.apple.link.systemProtocol.FocusConfiguration'],
  'parameters' => [{ 'name' => 'profile', 'isOptional' => true,
    'valueType' => { 'entity' => { 'wrapper' => { 'typeName' => 'BarlineProfileEntity' } } } }]
}
AppIntentsTopology.validate_metadata(metadata)
metadata.each_key do |kind|
  missing = metadata.merge(kind => {})
  rejected = false
  begin
    AppIntentsTopology.validate_metadata(missing)
  rescue ArgumentError
    rejected = true
  end
  raise 'missing extracted metadata was accepted' unless rejected
end
focus_mutations = [
  ->(f) { f['systemProtocols'] = [] },
  ->(f) { f.delete('parameters') },
  ->(f) { f['parameters'] = [] },
  ->(f) { f['parameters'] *= 2 },
  ->(f) { f['parameters'].first['isOptional'] = false },
  ->(f) { f['parameters'].first['valueType']['entity']['wrapper']['typeName'] = 'UnrelatedEntity' }
]
focus_mutations.each do |mutate|
  copy = Marshal.load(Marshal.dump(metadata))
  mutate.call(copy['actions']['BarlineFocusFilter'])
  rejected = false
  begin
    AppIntentsTopology.validate_metadata(copy)
  rescue ArgumentError
    rejected = true
  end
  raise 'invalid Focus Filter metadata was accepted' unless rejected
end
puts "PASS: #{mutations.length + focus_mutations.length + 5} App Intents topology/metadata regression cases"
