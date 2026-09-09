import Foundation

public enum TemporaryRevealJournalError: Error, Equatable, Sendable {
    case invalidEntries
    case invalidJournal
    case unavailable
}

/// Actor-isolated compensation storage. Corruption is preserved for explicit
/// recovery rather than silently discarding pending restoration intent.
public actor TemporaryRevealJournal {
    public struct Entry: Codable, Equatable, Sendable {
        public let id: UUID
        public let checkpoint: TemporaryRevealRestoration
        public let createdAt: Date

        public init(
            id: UUID = UUID(), checkpoint: TemporaryRevealRestoration,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.checkpoint = checkpoint
            self.createdAt = createdAt
        }
    }

    public static let maximumEntries = 64
    public static let maximumBytes = 1024 * 1024
    private let directoryURL: URL
    private let fileManager = FileManager.default
    private var fileURL: URL {
        directoryURL.appendingPathComponent("temporary-reveals.json")
    }

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func load() throws -> [Entry] {
        do {
            try rejectSymbolicLink(directoryURL)
            guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
            try validateDirectory()
            try rejectSymbolicLink(fileURL)
            guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  size.intValue <= Self.maximumBytes
            else { throw TemporaryRevealJournalError.invalidJournal }
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard data.count <= Self.maximumBytes,
                  let entries = try? JSONDecoder().decode([Entry].self, from: data),
                  Self.valid(entries)
            else { throw TemporaryRevealJournalError.invalidJournal }
            return entries
        } catch let error as TemporaryRevealJournalError {
            throw error
        } catch {
            throw TemporaryRevealJournalError.unavailable
        }
    }

    public func replace(_ entries: [Entry]) throws {
        guard Self.valid(entries) else { throw TemporaryRevealJournalError.invalidEntries }
        do {
            // Never overwrite an unreadable or corrupt prior journal, including
            // when the caller believes there are no outstanding entries.
            _ = try load()
            let data = try JSONEncoder().encode(entries)
            guard data.count <= Self.maximumBytes else { throw TemporaryRevealJournalError.invalidEntries }
            try fileManager.createDirectory(
                at: directoryURL, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try validateDirectory()
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch let error as TemporaryRevealJournalError {
            throw error
        } catch {
            throw TemporaryRevealJournalError.unavailable
        }
    }

    public func removeAll() throws {
        try replace([])
    }

    /// Only for an explicit user decision to keep current item positions.
    /// Preserve even undecodable compensation data before starting a new journal.
    public func discardPreservingBackup() throws {
        do {
            try rejectSymbolicLink(directoryURL)
            if fileManager.fileExists(atPath: directoryURL.path) {
                try validateDirectory()
                try rejectSymbolicLink(fileURL)
                if fileManager.fileExists(atPath: fileURL.path) {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    guard attributes[.type] as? FileAttributeType == .typeRegular else {
                        throw TemporaryRevealJournalError.invalidJournal
                    }
                    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
                    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                    let backup = directoryURL.appendingPathComponent(
                        "temporary-reveals-discarded-\(UUID().uuidString).json"
                    )
                    // Same-directory rename preserves the original bytes without
                    // reading an unbounded or corrupt file into memory.
                    try fileManager.moveItem(at: fileURL, to: backup)
                }
            }
            try replace([])
        } catch let error as TemporaryRevealJournalError {
            throw error
        } catch {
            throw TemporaryRevealJournalError.unavailable
        }
    }

    private func validateDirectory() throws {
        let attributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw TemporaryRevealJournalError.invalidJournal
        }
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        // fileExists follows links and returns false for a dangling link.
        // Check the link itself before treating a missing journal as empty.
        guard (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) == nil else {
            throw TemporaryRevealJournalError.invalidJournal
        }
    }

    private static func valid(_ entries: [Entry]) -> Bool {
        entries.count <= maximumEntries &&
            Set(entries.map(\.id)).count == entries.count &&
            Set(entries.map(\.checkpoint.itemID)).count == entries.count &&
            entries.allSatisfy {
                $0.checkpoint.isValid && $0.createdAt.timeIntervalSinceReferenceDate.isFinite
            }
    }
}
