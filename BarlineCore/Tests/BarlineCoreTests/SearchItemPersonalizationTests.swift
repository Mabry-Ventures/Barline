//
//  SearchItemPersonalizationTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Local search favorites and aliases")
struct SearchItemPersonalizationTests {
    private let first = MenuBarItemID(bundleIdentifier: "com.example.fixture", accessibilityIdentifier: "first")
    private let second = MenuBarItemID(bundleIdentifier: "com.example.fixture", accessibilityIdentifier: "second")

    @Test("Same-title items keep independent favorites and aliases")
    func independentStableIdentity() throws {
        let preferences = try SearchItemPersonalization.empty.settingFavorite(true, for: first)
            .settingAlias("  My Battery  ", for: second)
        #expect(preferences.isFavorite(first))
        #expect(!preferences.isFavorite(second))
        #expect(preferences.alias(for: first) == nil)
        #expect(preferences.alias(for: second) == "My Battery")
        #expect(try SearchItemPersonalization.decode(preferences.encoded()) == preferences)
    }

    @Test("Removing one preference preserves the other and blank alias removes only alias")
    func removal() throws {
        let preferences = try SearchItemPersonalization.empty.settingFavorite(true, for: first)
            .settingAlias("Work Battery", for: first)
        let noFavorite = try preferences.settingFavorite(false, for: first)
        #expect(noFavorite.alias(for: first) == "Work Battery")
        #expect(try noFavorite.settingAlias("  ", for: first).entries.isEmpty)
        #expect(try preferences.settingAlias("", for: first).isFavorite(first))
    }

    @Test("Aliases have byte and character bounds and reject controls")
    func aliasBounds() throws {
        #expect(try SearchItemPersonalization.validatedAlias(String(repeating: "a", count: 64)) != nil)
        for alias in [String(repeating: "a", count: 65), "bad\nname", "bad\u{0000}name", String(repeating: "👨‍👩‍👧‍👦", count: 64)] {
            #expect(throws: SearchItemPersonalization.ValidationError.invalidAlias) {
                try SearchItemPersonalization.validatedAlias(alias)
            }
        }
    }

    @Test("Rejects duplicate, invalid, and oversized identities")
    func identityValidation() throws {
        let entry = SearchItemPersonalization.Entry(itemID: first, isFavorite: true)
        #expect(throws: SearchItemPersonalization.ValidationError.duplicateIdentity) {
            try SearchItemPersonalization(entries: [entry, entry])
        }
        for identity in [MenuBarItemID(bundleIdentifier: ""), MenuBarItemID(bundleIdentifier: "com.example", title: String(repeating: "x", count: 513))] {
            #expect(throws: SearchItemPersonalization.ValidationError.invalidIdentity) {
                try SearchItemPersonalization.empty.settingFavorite(true, for: identity)
            }
        }
    }

    @Test("Malformed, future-version and oversized archives fail closed")
    func archiveBounds() throws {
        #expect(throws: (any Error).self) { try SearchItemPersonalization.decode(Data("not json".utf8)) }
        #expect(throws: SearchItemPersonalization.ValidationError.unsupportedVersion) {
            try SearchItemPersonalization.decode(Data("{\"schemaVersion\":2,\"entries\":[]}".utf8))
        }
        #expect(throws: SearchItemPersonalization.ValidationError.tooLarge) {
            try SearchItemPersonalization.decode(Data(count: SearchItemPersonalization.maximumEncodedBytes + 1))
        }
        let entries = (0 ... SearchItemPersonalization.maximumEntries).map {
            SearchItemPersonalization.Entry(itemID: MenuBarItemID(bundleIdentifier: "com.example", title: "Item \($0)"))
        }
        #expect(throws: SearchItemPersonalization.ValidationError.tooManyEntries) {
            try SearchItemPersonalization(entries: entries)
        }
    }

    @Test("User alias participates in existing deterministic ranking without changing identity")
    func aliasRanking() throws {
        let preferences = try SearchItemPersonalization.empty.settingAlias("juice", for: first)
        let document = SearchDocument(
            id: first.searchDocumentID, kind: .menuBarItem, entity: .menuBarItem(first), title: "Battery",
            aliases: [preferences.alias(for: first)].compactMap(\.self)
        )
        let index = try DeterministicSearchIndex(documents: [document])
        #expect(index.search("juice").first?.document.entity == .menuBarItem(first))
        #expect(index.search("juice").first?.reasons.contains(.exactAlias) == true)
    }
}
