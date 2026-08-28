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
    public static let maximumArchiveByteCount = 4 * 1024 * 1024
    public static let maximumProfileCount = 256
    public static let maximumCollectionCount = 2048
    public static let maximumStringLength = 1024

    private static let maximumObjectFieldCount = 64
    private static let maximumNestingDepth = 16
    private let validator: ProfileValidator

    public init(validator: ProfileValidator = ProfileValidator()) {
        self.validator = validator
    }

    public func encode(_ profile: BarlineProfile) throws -> Data {
        try validator.validate(profile)
        let data = try makeEncoder().encode(profile)
        try preflightEncodedJSON(data)
        return data
    }

    public func decode(_ data: Data) throws -> BarlineProfile {
        try preflightEncodedJSON(data)
        let migrated = try ProfileMigrator().migrate(data)
        try preflightEncodedJSON(migrated)
        let profile = try makeDecoder().decode(BarlineProfile.self, from: migrated)
        try validator.validate(profile)
        return profile
    }

    public func export(_ profiles: [BarlineProfile], at date: Date = Date()) throws -> Data {
        guard profiles.count <= Self.maximumProfileCount else {
            throw ProfileValidationError.archiveLimitExceeded("profile count")
        }
        try validator.validate(profiles)
        let data = try makeEncoder().encode(ProfileArchive(exportedAt: date, profiles: profiles))
        guard data.count <= Self.maximumArchiveByteCount else {
            throw ProfileValidationError.archiveTooLarge(data.count)
        }
        try preflightEncodedJSON(data)
        return data
    }

    public func importArchive(_ data: Data) throws -> ProfileArchive {
        guard data.count <= Self.maximumArchiveByteCount else {
            throw ProfileValidationError.archiveTooLarge(data.count)
        }
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
        try preflight(document, depth: 0)
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
        guard profileDocuments.count <= Self.maximumProfileCount else {
            throw ProfileValidationError.archiveLimitExceeded("profile count")
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

    private func preflight(_ value: Any, depth: Int) throws {
        guard depth <= Self.maximumNestingDepth else {
            throw ProfileValidationError.archiveLimitExceeded("nesting depth")
        }
        if let string = value as? String {
            guard string.count <= Self.maximumStringLength else {
                throw ProfileValidationError.archiveLimitExceeded("string length")
            }
            return
        }
        if let array = value as? [Any] {
            guard array.count <= Self.maximumCollectionCount else {
                throw ProfileValidationError.archiveLimitExceeded("collection count")
            }
            for element in array {
                try preflight(element, depth: depth + 1)
            }
            return
        }
        if let object = value as? [String: Any] {
            guard object.count <= Self.maximumObjectFieldCount else {
                throw ProfileValidationError.archiveLimitExceeded("object field count")
            }
            for (key, nestedValue) in object {
                guard key.count <= Self.maximumStringLength else {
                    throw ProfileValidationError.archiveLimitExceeded("field name length")
                }
                try preflight(nestedValue, depth: depth + 1)
            }
        }
    }

    private func preflightEncodedJSON(_ data: Data) throws {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProfileValidationError.malformedDocument(String(describing: error))
        }
        try preflight(value, depth: 0)
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
