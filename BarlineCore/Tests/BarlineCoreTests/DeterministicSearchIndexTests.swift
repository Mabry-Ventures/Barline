//
//  DeterministicSearchIndexTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Deterministic local search")
struct DeterministicSearchIndexTests {
    @Test("Opaque search identities preserve punctuation and stable-ID field boundaries")
    func opaqueDocumentIdentity() {
        #expect(SearchDocumentID("a-b") != SearchDocumentID("a b"))
        let accessibility = MenuBarItemID(
            bundleIdentifier: "com.example.clock",
            accessibilityIdentifier: "clock"
        )
        let title = MenuBarItemID(
            bundleIdentifier: "com.example.clock",
            title: "clock"
        )
        #expect(accessibility.description == title.description)
        #expect(accessibility.searchDocumentID != title.searchDocumentID)
        #expect(accessibility.searchDocumentID.value.contains("accessibility:5:clock"))
    }

    @Test("Ranks exact aliases, titles, prefixes, and fuzzy matches")
    func textRanking() throws {
        let index = try makeIndex()

        #expect(index.search("juice").first?.document.id == .init("item.battery"))
        #expect(index.search("Battery").first?.reasons.contains(.exactTitle) == true)
        #expect(index.search("batt").first?.reasons.contains(.prefix) == true)
        #expect(index.search("batery").first?.reasons.contains(.fuzzy) == true)
    }

    @Test("Searches app, bundle, group, profile, keyword, and curated synonyms")
    func metadataRanking() throws {
        let index = try makeIndex()

        #expect(index.search("Example Display").first?.document.id == .init("item.display"))
        #expect(index.search("com.example.display").first?.document.id == .init("item.display"))
        #expect(index.search("essentials").first?.document.id == .init("item.battery"))
        #expect(index.search("presenting").first?.document.id == .init("item.display"))
        #expect(index.search("external").first?.document.id == .init("item.display"))
        #expect(index.search("power").first?.document.id == .init("item.battery"))
    }

    @Test("Recency breaks otherwise equal matches without producing text-free results")
    func boundedRecency() throws {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let old = itemDocument(id: "item.old", title: "Sync", lastUsedAt: now.addingTimeInterval(-30 * 86400))
        let recent = itemDocument(id: "item.recent", title: "Sync", lastUsedAt: now.addingTimeInterval(-60))
        let unrelated = itemDocument(id: "item.unrelated", title: "Clock", lastUsedAt: now)
        let index = try DeterministicSearchIndex(documents: [old, recent, unrelated])

        let results = index.search("sync", now: now)

        #expect(results.map(\.document.id) == [.init("item.recent"), .init("item.old")])
        #expect(results.first?.reasons.contains(.recentUse) == true)
    }

    @Test("Stable identifiers replace and delete records without stale results")
    func updatesAndDeletion() throws {
        var index = try DeterministicSearchIndex(documents: [
            itemDocument(id: "item.sync", title: "Old Name"),
        ])

        try index.upsert(itemDocument(id: "item.sync", title: "New Name"))
        #expect(index.count == 1)
        #expect(index.search("old").isEmpty)
        #expect(index.search("new").first?.document.id == .init("item.sync"))

        index.remove(id: .init("item.sync"))
        #expect(index.isEmpty)
        #expect(index.search("new").isEmpty)
    }

    @Test("Kind synchronization removes only stale records of that kind")
    func synchronization() throws {
        let profile = SearchDocument(
            id: .init("profile.work"),
            kind: .profile,
            entity: .profile(.init("work")),
            title: "Work"
        )
        var index = try DeterministicSearchIndex(documents: [
            itemDocument(id: "item.one", title: "One"),
            itemDocument(id: "item.two", title: "Two"),
            profile,
        ])

        try index.synchronize(
            kind: .menuBarItem,
            documents: [itemDocument(id: "item.two", title: "Second")]
        )

        #expect(index.count == 2)
        #expect(index.search("one").isEmpty)
        #expect(index.search("second").first?.document.id == .init("item.two"))
        #expect(index.search("work").first?.document.id == .init("profile.work"))
    }

    @Test("Rejects invalid and duplicate stable records")
    func invalidRecords() throws {
        let invalid = SearchDocument(
            id: .init(""),
            kind: .profile,
            entity: .profile(.init("profile")),
            title: "Profile"
        )
        #expect(throws: SearchIndexError.invalidDocument(.init(""))) {
            try DeterministicSearchIndex(documents: [invalid])
        }

        let duplicate = itemDocument(id: "item.same", title: "Same")
        #expect(throws: SearchIndexError.duplicateIdentifier(.init("item.same"))) {
            try DeterministicSearchIndex(documents: [duplicate, duplicate])
        }
    }

    @Test("Normalization is case, width, punctuation, and diacritic insensitive")
    func normalization() throws {
        let item = itemDocument(id: "item.cafe", title: "Café Wi-Fi")
        let index = try DeterministicSearchIndex(documents: [item])

        #expect(index.search("CAFE wifi").first?.document.id == .init("item.cafe"))
    }

    @Test("Ordinary local search stays under its p95-style budget")
    func performanceBudget() throws {
        // This is intentionally larger than an ordinary menu-bar inventory while
        // remaining representative of Barline's bounded local index.
        let documents = (0 ..< 250).map { index in
            itemDocument(
                id: "item.\(index)",
                title: "Utility \(index)",
                aliases: ["tool \(index)"],
                keywords: ["status helper"]
            )
        }
        let index = try DeterministicSearchIndex(documents: documents)
        var durations = [Duration]()
        let clock = ContinuousClock()

        let queries = ["Utility 42", "tool 175", "statuz", "helper", "Utility 249"]
        for query in queries {
            _ = index.search(query) // Exclude one-time allocation/cache warmup.
        }
        for _ in 0 ..< 20 {
            for query in queries {
                let start = clock.now
                _ = index.search(query)
                durations.append(start.duration(to: clock.now))
            }
        }
        durations.sort()

        let percentile95 = durations[Int(Double(durations.count - 1) * 0.95)]
        #expect(percentile95 < .milliseconds(50))
    }
}

private func makeIndex() throws -> DeterministicSearchIndex {
    try DeterministicSearchIndex(documents: [
        itemDocument(
            id: "item.battery",
            title: "Battery",
            aliases: ["Juice"],
            groups: ["Essentials"]
        ),
        SearchDocument(
            id: .init("item.display"),
            kind: .menuBarItem,
            entity: .menuBarItem(
                .init(bundleIdentifier: "com.example.display", accessibilityIdentifier: "display")
            ),
            title: "Display Controller",
            owningApplication: "Example Display",
            bundleIdentifier: "com.example.display",
            profileMemberships: ["Presentation"],
            keywords: ["external monitor"]
        ),
    ])
}

private func itemDocument(
    id: String,
    title: String,
    aliases: [String] = [],
    groups: [String] = [],
    keywords: [String] = [],
    lastUsedAt: Date? = nil
) -> SearchDocument {
    SearchDocument(
        id: .init(id),
        kind: .menuBarItem,
        entity: .menuBarItem(
            .init(bundleIdentifier: "com.example.\(id)", accessibilityIdentifier: id)
        ),
        title: title,
        aliases: aliases,
        groups: groups,
        keywords: keywords,
        lastUsedAt: lastUsedAt
    )
}
