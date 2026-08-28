//
//  SpotlightIndexModelsTests.swift
//  Barline
//

@testable import BarlineCore
import Testing

@Suite("Privacy-bounded Spotlight records")
struct SpotlightIndexModelsTests {
    @Test("Stable identifiers round-trip and retain entity kind")
    func stableIdentifier() throws {
        let document = makeDocument()
        let record = try SpotlightIndexRecord(document: document)

        #expect(record.uniqueIdentifier == "barline.search.menuBarItem.item.display")
        #expect(record.domainIdentifier == "com.mabryventures.barline.search")
        #expect(record.kind == .menuBarItem)
        #expect(try SpotlightIndexRecord.documentID(fromUniqueIdentifier: record.uniqueIdentifier) == document.id)
    }

    @Test("Only bounded public search fields become keywords")
    func boundedKeywords() throws {
        let document = makeDocument(
            aliases: ["Monitor", "monitor"],
            groups: ["Utilities"],
            profileMemberships: ["Presentation"],
            synonyms: ["Screen"],
            keywords: [String(repeating: "x", count: 300)]
        )

        let record = try SpotlightIndexRecord(document: document)

        #expect(record.keywords.contains("Example Display"))
        #expect(record.keywords.contains("com.example.display"))
        #expect(record.keywords.filter { $0.lowercased() == "monitor" }.count == 1)
        #expect(record.keywords.allSatisfy { $0.count <= 128 })
        #expect(record.keywords.count <= 64)
    }

    @Test("Invalid records and foreign identifiers fail closed")
    func invalidInput() {
        let invalid = SearchDocument(
            id: .init(""),
            kind: .command,
            entity: .command(.init("restore")),
            title: "Restore"
        )
        #expect(throws: SpotlightIndexRecordError.invalidDocument(.init(""))) {
            try SpotlightIndexRecord(document: invalid)
        }
        #expect(throws: SpotlightIndexRecordError.malformedUniqueIdentifier("foreign.item")) {
            try SpotlightIndexRecord.documentID(fromUniqueIdentifier: "foreign.item")
        }
    }
}

private func makeDocument(
    aliases: [String] = [],
    groups: [String] = [],
    profileMemberships: [String] = [],
    synonyms: [String] = [],
    keywords: [String] = []
) -> SearchDocument {
    SearchDocument(
        id: .init("item.display"),
        kind: .menuBarItem,
        entity: .menuBarItem(
            .init(bundleIdentifier: "com.example.display", accessibilityIdentifier: "display")
        ),
        title: "Display Controller",
        owningApplication: "Example Display",
        bundleIdentifier: "com.example.display",
        aliases: aliases,
        groups: groups,
        profileMemberships: profileMemberships,
        synonyms: synonyms,
        keywords: keywords
    )
}
