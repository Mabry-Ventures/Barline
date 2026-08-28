#!/usr/bin/env ruby

require "json"

unless ARGV.length == 5
  warn "usage: generate-spdx-sbom.rb ROOT VERSION BUILD COMMIT_SHA OUTPUT"
  exit 2
end

root, version, build, commit_sha, output = ARGV
lockfiles = ["Barline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]

pins = lockfiles.map do |relative|
  path = File.join(root, relative)
  next [] unless File.file?(path)

  JSON.parse(File.read(path)).fetch("pins", [])
end.flatten.uniq { |pin| pin.fetch("identity") }

abort "error: no Swift package lockfile entries are available for the SBOM" if pins.empty?

spdx_id = lambda do |identity|
  normalized = identity.gsub(/[^A-Za-z0-9.-]/, "-")
  "SPDXRef-Package-#{normalized}"
end

root_id = "SPDXRef-Package-Barline"
packages = [{
  "SPDXID" => root_id,
  "name" => "Barline",
  "versionInfo" => version,
  "packageFileName" => "Barline-#{version}.zip",
  "downloadLocation" => "NOASSERTION",
  "filesAnalyzed" => false,
  "licenseConcluded" => "GPL-3.0-or-later",
  "licenseDeclared" => "GPL-3.0-or-later",
  "copyrightText" => "NOASSERTION",
  "primaryPackagePurpose" => "APPLICATION",
  "summary" => "Barline build #{build} from commit #{commit_sha}"
}]

dependency_packages = pins.map do |pin|
  state = pin.fetch("state", {})
  version_info = state["version"] || state["revision"] || "NOASSERTION"
  {
    "SPDXID" => spdx_id.call(pin.fetch("identity")),
    "name" => pin.fetch("identity"),
    "versionInfo" => version_info,
    "downloadLocation" => pin["location"] || "NOASSERTION",
    "filesAnalyzed" => false,
    "licenseConcluded" => "NOASSERTION",
    "licenseDeclared" => "NOASSERTION",
    "copyrightText" => "NOASSERTION",
    "primaryPackagePurpose" => "LIBRARY",
    "sourceInfo" => "SwiftPM revision #{state["revision"] || "NOASSERTION"}"
  }
end
packages.concat(dependency_packages)

relationships = [{
  "spdxElementId" => "SPDXRef-DOCUMENT",
  "relationshipType" => "DESCRIBES",
  "relatedSpdxElement" => root_id
}]
relationships.concat(dependency_packages.map do |package|
  {
    "spdxElementId" => root_id,
    "relationshipType" => "DEPENDS_ON",
    "relatedSpdxElement" => package.fetch("SPDXID")
  }
end)

document = {
  "spdxVersion" => "SPDX-2.3",
  "dataLicense" => "CC0-1.0",
  "SPDXID" => "SPDXRef-DOCUMENT",
  "name" => "Barline-#{version}",
  "documentNamespace" => "https://github.com/Mabry-Ventures/Barline/spdx/Barline-#{version}-#{commit_sha}",
  "creationInfo" => {
    "created" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "creators" => ["Tool: Barline generate-spdx-sbom.rb"]
  },
  "documentDescribes" => [root_id],
  "comment" => "Commit #{commit_sha}, build #{build}",
  "packages" => packages,
  "relationships" => relationships
}

File.write(output, JSON.pretty_generate(document) + "\n")
