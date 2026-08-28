//
//  ProfileCodec.swift
//  Barline
//

import Foundation

public struct ProfileArchive: Codable, Hashable, Sendable {
    public let formatVersion: Int
    public let exportedAt: Date
    public let profiles: [BarlineProfile]

    public init(
        formatVersion: Int = ProfileSchema.archiveFormatVersion,
        exportedAt: Date = Date(),
        profiles: [BarlineProfile]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.profiles = profiles
    }
}

public struct ProfileCodec: Sendable {
    private let validator: ProfileValidator

    public init(validator: ProfileValidator = ProfileValidator()) {
        self.validator = validator
    }

    public func encode(_ profile: BarlineProfile) throws -> Data {
        try validator.validate(profile)
        return try makeEncoder().encode(profile)
    }

    public func decode(_ data: Data) throws -> BarlineProfile {
        let migrated = try ProfileMigrator().migrate(data)
        let profile = try makeDecoder().decode(BarlineProfile.self, from: migrated)
        try validator.validate(profile)
        return profile
    }

    public func export(_ profiles: [BarlineProfile], at date: Date = Date()) throws -> Data {
        try validator.validate(profiles)
        return try makeEncoder().encode(ProfileArchive(exportedAt: date, profiles: profiles))
    }

    public func importArchive(_ data: Data) throws -> ProfileArchive {
        let document: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProfileValidationError.malformedDocument("archive must be a JSON object")
            }
            document = decoded
        } catch {
            if let validationError = error as? ProfileValidationError {
                throw validationError
            }
            throw ProfileValidationError.malformedDocument(String(describing: error))
        }
        guard let formatVersion = document["formatVersion"] as? Int else {
            throw ProfileValidationError.malformedDocument("formatVersion is required")
        }
        guard formatVersion == ProfileSchema.archiveFormatVersion else {
            throw ProfileValidationError.unsupportedArchiveVersion(formatVersion)
        }
        guard let exportedAtValue = document["exportedAt"],
              let profileDocuments = document["profiles"] as? [[String: Any]]
        else {
            throw ProfileValidationError.malformedDocument("exportedAt and profiles are required")
        }

        let exportedAtData = try JSONSerialization.data(withJSONObject: ["value": exportedAtValue])
        struct DateBox: Decodable { let value: Date }
        let exportedAt: Date
        do {
            exportedAt = try makeDecoder().decode(DateBox.self, from: exportedAtData).value
        } catch {
            throw ProfileValidationError.malformedDocument("exportedAt is invalid")
        }

        let profiles = try profileDocuments.map { document in
            let profileData = try JSONSerialization.data(withJSONObject: document)
            return try decode(profileData)
        }
        try validator.validate(profiles)
        return ProfileArchive(formatVersion: formatVersion, exportedAt: exportedAt, profiles: profiles)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public struct ProfileMigrator: Sendable {
    public init() {}

    public func migrate(_ data: Data) throws -> Data {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProfileValidationError.malformedDocument(String(describing: error))
        }
        guard var document = object as? [String: Any] else {
            throw ProfileValidationError.malformedDocument("profile must be a JSON object")
        }
        guard let version = document["schemaVersion"] as? Int else {
            throw ProfileValidationError.malformedDocument("schemaVersion is required")
        }
        guard (1 ... ProfileSchema.currentVersion).contains(version) else {
            throw ProfileValidationError.unsupportedSchemaVersion(version)
        }

        var migratedVersion = version
        while migratedVersion < ProfileSchema.currentVersion {
            switch migratedVersion {
            case 1: migrateV1ToV2(&document)
            case 2: migrateV2ToV3(&document)
            default: throw ProfileValidationError.unsupportedSchemaVersion(migratedVersion)
            }
            migratedVersion += 1
            document["schemaVersion"] = migratedVersion
        }
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    private func migrateV1ToV2(_ document: inout [String: Any]) {
        let visible = document.removeValue(forKey: "visibleItemOrder") as? [Any] ?? []
        let hidden = document.removeValue(forKey: "hiddenItemOrder") as? [Any] ?? []
        let alwaysHidden = document.removeValue(forKey: "alwaysHiddenItemOrder") as? [Any] ?? []
        document["layout"] = ["visible": visible, "hidden": hidden, "alwaysHidden": alwaysHidden]
        document["groups"] = document["groups"] ?? []
        document["spacers"] = document["spacers"] ?? []
        document["displayOverrides"] = document["displayOverrides"] ?? []
    }

    private func migrateV2ToV3(_ document: inout [String: Any]) {
        document["appearance"] = document["appearance"] ?? [
            "gradientHex": [], "showsBorder": false, "showsShadow": false,
            "shape": "standard", "itemSpacing": 0,
        ]
        document["shelfBehavior"] = document["shelfBehavior"] ?? [
            "isEnabled": false, "followsActiveDisplay": true,
        ]
        document["revealTriggers"] = document["revealTriggers"] ?? [
            "click": true, "hover": false, "scroll": false,
        ]
        document["autoRehide"] = document["autoRehide"] ?? [
            "isEnabled": true, "delaySeconds": 5,
        ]
        document["applicationMenuOverlapBehavior"] =
            document["applicationMenuOverlapBehavior"] ?? "hideWhenNeeded"
    }
}
