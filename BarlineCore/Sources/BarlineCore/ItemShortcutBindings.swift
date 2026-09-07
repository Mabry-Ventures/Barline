//
//  ItemShortcutBindings.swift
//  Barline
//

import Foundation

/// Portable physical-key binding; platform registration remains in the app.
public struct ItemShortcutChord: Codable, Hashable, Sendable {
    public let keyCode: Int
    public let modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isValid: Bool {
        (0 ... 127).contains(keyCode) && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode) &&
            modifiers > 0 && modifiers <= 15 && modifiers != 4
    }
}

public struct ItemShortcutBindings: Codable, Equatable, Sendable {
    public static let maximumEntries = 128
    public static let maximumEncodedBytes = 256 * 1024

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidVersion, invalidIdentity, invalidChord, duplicateIdentity, duplicateChord, tooLarge
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let itemID: MenuBarItemID
        public let chord: ItemShortcutChord

        public init(itemID: MenuBarItemID, chord: ItemShortcutChord) {
            self.itemID = itemID
            self.chord = chord
        }
    }

    public let schemaVersion: Int
    public private(set) var entries: [Entry]

    public init() {
        schemaVersion = 1
        entries = []
    }

    public init(entries: [Entry]) throws {
        schemaVersion = 1
        self.entries = entries
        try validate()
    }

    public func setting(_ chord: ItemShortcutChord?, for itemID: MenuBarItemID) throws -> Self {
        var updated = entries.filter { $0.itemID != itemID }
        if let chord {
            updated.append(Entry(itemID: itemID, chord: chord))
        }
        updated.sort { $0.itemID.searchDocumentID.value < $1.itemID.searchDocumentID.value }
        return try Self(entries: updated)
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw ValidationError.invalidVersion }
        guard entries.count <= Self.maximumEntries else { throw ValidationError.tooLarge }
        var identities = Set<MenuBarItemID>()
        var chords = Set<ItemShortcutChord>()
        for entry in entries {
            let fields = [entry.itemID.bundleIdentifier, entry.itemID.accessibilityIdentifier,
                          entry.itemID.title, entry.itemID.alias, entry.itemID.fallbackFingerprint].compactMap(\.self)
            guard entry.itemID.isPlausiblyStable, fields.allSatisfy({ $0.utf8.count <= 512 }) else {
                throw ValidationError.invalidIdentity
            }
            guard entry.chord.isValid else { throw ValidationError.invalidChord }
            guard identities.insert(entry.itemID).inserted else { throw ValidationError.duplicateIdentity }
            guard chords.insert(entry.chord).inserted else { throw ValidationError.duplicateChord }
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
}

/// A release is actionable only after a matching press; repeats never multiply actions.
public struct ShortcutPressCycle: Sendable {
    private var pressed = Set<UInt32>()

    public init() {}

    public mutating func keyDown(_ id: UInt32) -> Bool {
        pressed.insert(id).inserted
    }

    public mutating func keyUp(_ id: UInt32) -> Bool {
        pressed.remove(id) != nil
    }

    public mutating func reset() {
        pressed.removeAll()
    }
}
