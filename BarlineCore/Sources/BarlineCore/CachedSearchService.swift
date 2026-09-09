//
//  CachedSearchService.swift
//  Barline
//

import Foundation

/// Keeps indexing and ranking on a serial executor outside the UI actor.
/// Cancellation is checked before replacing the last complete index and after
/// ranking, so a cancelled request never yields partial results to the caller.
public actor CachedSearchService {
    public static let maximumResultCount = 200
    private var documents: [SearchDocument] = []
    private var index = try? DeterministicSearchIndex()
    private(set) var indexBuildCount = 0

    public init() {}

    public func search(_ query: String, documents proposedDocuments: [SearchDocument]) throws -> [SearchResult] {
        try Task.checkCancellation()
        if index == nil || proposedDocuments != documents {
            let replacement = try DeterministicSearchIndex(documents: proposedDocuments)
            try Task.checkCancellation()
            index = replacement
            documents = proposedDocuments
            indexBuildCount += 1
        }
        let results = index?.search(query, limit: Self.maximumResultCount) ?? []
        try Task.checkCancellation()
        return results
    }
}
