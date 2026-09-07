//
//  SearchItemPersonalization.swift
//  Barline
//

import Foundation

/// Local search presentation only. User aliases never change mutation identity.
public struct SearchItemPersonalization: Codable, Equatable, Sendable {
    public static let maximumEntries = 512
    public static let maximumEncodedBytes = 512 * 1024
    public static let maximumAliasCharacters = 64

    public enum ValidationError: Error, Equatable, Sendable {
        case unsupportedVersion
        case tooManyEntries
        case invalidIdentity
        case duplicateIdentity
        case invalidAlias
        case tooLarge
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let itemID: MenuBarItemID
        public let isFavorite: Bool
        public let alias: String?

        public init(itemID: MenuBarItemID, isFavorite: Bool = false, alias: String? = nil) {
            self.itemID = itemID
            self.isFavorite = isFavorite
            self.alias = alias
        }
    }

    public let schemaVersion: Int
    public private(set) var entries: [Entry]

    public init(entries: [Entry]) throws {
        schemaVersion = 1
        self.entries = entries
        try validate()
    }

    public init() {
        schemaVersion = 1
        entries = []
    }

    public static let empty = SearchItemPersonalization()

    public func isFavorite(_ itemID: MenuBarItemID) -> Bool {
        entries.first { $0.itemID == itemID }?.isFavorite == true
    }

    public func alias(for itemID: MenuBarItemID) -> String? {
        entries.first { $0.itemID == itemID }?.alias
    }

    public func settingFavorite(_ value: Bool, for itemID: MenuBarItemID) throws -> Self {
        try replacing(Entry(itemID: itemID, isFavorite: value, alias: alias(for: itemID)))
    }

    public func settingAlias(_ value: String, for itemID: MenuBarItemID) throws -> Self {
        try replacing(Entry(itemID: itemID, isFavorite: isFavorite(itemID), alias: Self.validatedAlias(value)))
    }

    public static func validatedAlias(_ value: String) throws -> String? {
        guard value.count <= maximumAliasCharacters, value.utf8.count <= 256,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw ValidationError.invalidAlias }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw ValidationError.unsupportedVersion }
        guard entries.count <= Self.maximumEntries else { throw ValidationError.tooManyEntries }
        var seen = Set<MenuBarItemID>()
        for entry in entries {
            let fields = [entry.itemID.bundleIdentifier, entry.itemID.accessibilityIdentifier,
                          entry.itemID.title, entry.itemID.alias, entry.itemID.fallbackFingerprint].compactMap(\.self)
            guard entry.itemID.isPlausiblyStable, fields.allSatisfy({ $0.utf8.count <= 512 }) else {
                throw ValidationError.invalidIdentity
            }
            guard seen.insert(entry.itemID).inserted else { throw ValidationError.duplicateIdentity }
            if let alias = entry.alias {
                guard try Self.validatedAlias(alias) == alias else { throw ValidationError.invalidAlias }
            }
        }
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumEncodedBytes else { throw ValidationError.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else { throw ValidationError.tooLarge }
        return data
    }

    private func replacing(_ replacement: Entry) throws -> Self {
        var updated = entries.filter { $0.itemID != replacement.itemID }
        if replacement.isFavorite || replacement.alias != nil {
            updated.append(replacement)
        }
        updated.sort { $0.itemID.searchDocumentID.value < $1.itemID.searchDocumentID.value }
        return try Self(entries: updated)
    }
}
