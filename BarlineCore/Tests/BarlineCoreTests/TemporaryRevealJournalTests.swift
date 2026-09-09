@testable import BarlineCore
import Foundation
import Testing

@Suite("Durable temporary reveal compensation")
struct TemporaryRevealJournalTests {
    @Test("Atomic replacement survives reopening with private filesystem permissions")
    func persistence() async throws {
        let directory = directoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = TemporaryRevealJournal(directoryURL: directory)
        #expect(try await journal.load().isEmpty)
        let entries = try [entry("one"), entry("two")]
        try await journal.replace(entries)
        let reopened = TemporaryRevealJournal(directoryURL: directory)
        #expect(try await reopened.load() == entries)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("temporary-reveals.json").path
        )
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try await journal.removeAll()
        #expect(try await reopened.load().isEmpty)
    }

    @Test("Duplicate item identities and duplicate journal identifiers fail before replacement")
    func duplicates() async throws {
        let directory = directoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = TemporaryRevealJournal(directoryURL: directory)
        let original = try entry("one")
        try await journal.replace([original])
        let sameItem = TemporaryRevealJournal.Entry(checkpoint: original.checkpoint)
        await #expect(throws: TemporaryRevealJournalError.invalidEntries) {
            try await journal.replace([original, sameItem])
        }
        let other = try entry("two")
        let sameID = TemporaryRevealJournal.Entry(id: original.id, checkpoint: other.checkpoint)
        await #expect(throws: TemporaryRevealJournalError.invalidEntries) {
            try await journal.replace([original, sameID])
        }
        #expect(try await journal.load() == [original])
    }

    @Test("Corrupt and oversized files are preserved and cannot be silently overwritten")
    func corruptJournal() async throws {
        let directory = directoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("temporary-reveals.json")
        let journal = TemporaryRevealJournal(directoryURL: directory)
        for data in [Data("broken".utf8), Data(repeating: 0, count: TemporaryRevealJournal.maximumBytes + 1)] {
            try data.write(to: file)
            await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.load() }
            await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.removeAll() }
            #expect(try Data(contentsOf: file) == data)
        }
    }

    @Test("Entry count is bounded and failed writes leave the prior journal intact")
    func countLimit() async throws {
        let directory = directoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = TemporaryRevealJournal(directoryURL: directory)
        let entries = try (0 ..< 64).map { try entry("item-\($0)") }
        try await journal.replace(entries)
        let excessive = try entries + [entry("extra")]
        await #expect(throws: TemporaryRevealJournalError.invalidEntries) { try await journal.replace(excessive) }
        #expect(try await journal.load() == entries)
    }

    @Test("A symlink journal is never read or overwritten")
    func symlink() async throws {
        let directory = directoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("original.json")
        try Data("[]".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("temporary-reveals.json"), withDestinationURL: target
        )
        let journal = TemporaryRevealJournal(directoryURL: directory)
        await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.load() }
        await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.removeAll() }
        await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.discardPreservingBackup() }
        #expect(try Data(contentsOf: target) == Data("[]".utf8))
        try FileManager.default.removeItem(at: target)
        await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.load() }
        await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.removeAll() }
        await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.discardPreservingBackup() }
    }

    @Test("Explicit discard preserves corrupt or oversized bytes and starts a usable journal")
    func explicitDiscard() async throws {
        let directory = directoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("temporary-reveals.json")
        let journal = TemporaryRevealJournal(directoryURL: directory)
        let payloads = [Data("broken".utf8), Data(repeating: 0, count: TemporaryRevealJournal.maximumBytes + 1)]
        for data in payloads {
            try data.write(to: file)
            try await journal.discardPreservingBackup()
            #expect(try await journal.load().isEmpty)
        }
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("temporary-reveals-discarded-") }
        #expect(backups.count == 2)
        let retained = try backups.map { try Data(contentsOf: $0) }
        for payload in payloads {
            #expect(retained.contains(payload))
        }
        for backup in backups {
            let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let replacement = try entry("new")
        try await journal.replace([replacement])
        #expect(try await journal.load() == [replacement])
    }

    @Test("Explicit discard is safe when no journal or directory exists")
    func discardWithoutJournal() async throws {
        let directory = directoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = TemporaryRevealJournal(directoryURL: directory)
        for _ in 0 ..< 2 {
            try await journal.discardPreservingBackup()
            #expect(try await journal.load().isEmpty)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("temporary-reveals.json"))
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.isEmpty)
    }

    @Test("Explicit discard rejects a symlink directory without modifying its target")
    func discardSymlinkDirectory() async throws {
        let directory = directoryURL()
        let target = directoryURL()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let file = target.appendingPathComponent("temporary-reveals.json")
        try Data("broken".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: target)
        let journal = TemporaryRevealJournal(directoryURL: directory)
        await #expect(throws: TemporaryRevealJournalError.invalidJournal) { try await journal.discardPreservingBackup() }
        #expect(try Data(contentsOf: file) == Data("broken".utf8))
    }

    private func directoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("barline-journal-test-\(UUID().uuidString)")
    }

    private func entry(_ name: String) throws -> TemporaryRevealJournal.Entry {
        let itemID = MenuBarItemID(bundleIdentifier: "test.journal", accessibilityIdentifier: name)
        let displayID = MenuBarDisplayID("primary")
        let snapshot = MenuBarSnapshot(
            generation: 1, capturedAt: Date(),
            items: [MenuBarItemDescriptor(id: itemID, section: .hidden, order: 0, displayID: displayID)],
            displayIDs: [displayID], activeSpaceIsValid: true
        )
        let checkpoint = try #require(TemporaryRevealRestoration(itemID: itemID, in: snapshot))
        return TemporaryRevealJournal.Entry(checkpoint: checkpoint)
    }
}
