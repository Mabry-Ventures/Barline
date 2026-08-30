//
//  CoreSpotlightIndexer.swift
//  Barline
//

import BarlineCore
@preconcurrency import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

enum CoreSpotlightIndexingError: Error, Equatable, Sendable {
    case unavailable
    case invalidDocument(SearchDocumentID)
    case operationFailed(code: Int)
}

/// Owns Barline's private Core Spotlight domain. The adapter indexes only the
/// privacy-bounded fields exposed by `SpotlightIndexRecord`.
actor CoreSpotlightIndexer {
    static let shared = CoreSpotlightIndexer()

    private let index: CSSearchableIndex
    private let replacementSemaphore = AsyncSemaphore(value: 1)

    init(indexName: String = "BarlineSearch") {
        index = CSSearchableIndex(name: indexName)
    }

    var isAvailable: Bool {
        CSSearchableIndex.isIndexingAvailable()
    }

    /// Replaces Barline's search domain so removed documents cannot remain
    /// discoverable after a profile, group, alias, or item is deleted.
    func replaceAll(with documents: [SearchDocument]) async throws {
        try await replacementSemaphore.waitUnlessCancelled()
        defer { replacementSemaphore.signal() }

        try Task.checkCancellation()
        guard isAvailable else { throw CoreSpotlightIndexingError.unavailable }
        let records = try documents.map(makeRecord)

        try await deleteDomain()
        try Task.checkCancellation()
        guard !records.isEmpty else { return }
        try await indexRecords(records)
    }

    /// Stable identifiers make indexing the same document an update.
    func upsert(_ documents: [SearchDocument]) async throws {
        guard isAvailable else { throw CoreSpotlightIndexingError.unavailable }
        let records = try documents.map(makeRecord)
        guard !records.isEmpty else { return }
        try await indexRecords(records)
    }

    func remove(documentIDs: [SearchDocumentID], kind: SearchDocumentKind) async throws {
        guard isAvailable else { throw CoreSpotlightIndexingError.unavailable }
        let identifiers = documentIDs.map {
            SpotlightIndexRecord.uniqueIdentifier(for: $0, kind: kind)
        }
        guard !identifiers.isEmpty else { return }

        try await withCheckedThrowingContinuation { continuation in
            index.deleteSearchableItems(withIdentifiers: identifiers) { error in
                Self.resume(continuation, error: error)
            }
        }
    }

    func removeAll() async throws {
        guard isAvailable else { throw CoreSpotlightIndexingError.unavailable }
        try await deleteDomain()
    }

    private func makeRecord(_ document: SearchDocument) throws -> SpotlightIndexRecord {
        do {
            return try SpotlightIndexRecord(document: document)
        } catch {
            throw CoreSpotlightIndexingError.invalidDocument(document.id)
        }
    }

    private func indexRecords(_ records: [SpotlightIndexRecord]) async throws {
        let searchableItems = records.map { record in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = record.title
            attributes.displayName = record.title
            attributes.keywords = record.keywords

            let item = CSSearchableItem(
                uniqueIdentifier: record.uniqueIdentifier,
                domainIdentifier: record.domainIdentifier,
                attributeSet: attributes
            )
            item.expirationDate = .distantFuture
            return item
        }

        try await withCheckedThrowingContinuation { continuation in
            index.indexSearchableItems(searchableItems) { error in
                Self.resume(continuation, error: error)
            }
        }
    }

    private func deleteDomain() async throws {
        try await withCheckedThrowingContinuation { continuation in
            index.deleteSearchableItems(
                withDomainIdentifiers: [SpotlightIndexRecord.domainIdentifier]
            ) { error in
                Self.resume(continuation, error: error)
            }
        }
    }

    private nonisolated static func resume(
        _ continuation: CheckedContinuation<Void, any Error>,
        error: (any Error)?
    ) {
        if let error = error as? NSError {
            continuation.resume(throwing: CoreSpotlightIndexingError.operationFailed(code: error.code))
        } else {
            continuation.resume()
        }
    }
}
