//
//  DeterministicSearchIndex.swift
//  Barline
//

import Foundation

public enum SearchIndexError: Error, Equatable, Sendable {
    case invalidDocument(SearchDocumentID)
    case duplicateIdentifier(SearchDocumentID)
}

public struct DeterministicSearchIndex: Sendable {
    private var records: [SearchDocumentID: IndexedSearchDocument] = [:]
    public let synonymMap: SearchSynonymMap

    public init(
        documents: [SearchDocument] = [],
        synonymMap: SearchSynonymMap = .curated
    ) throws {
        self.synonymMap = synonymMap
        for document in documents {
            guard records[document.id] == nil else {
                throw SearchIndexError.duplicateIdentifier(document.id)
            }
            try upsert(document)
        }
    }

    public var count: Int {
        records.count
    }

    public var isEmpty: Bool {
        records.isEmpty
    }

    /// Replaces a prior record with the same stable identifier atomically.
    public mutating func upsert(_ document: SearchDocument) throws {
        guard document.isValid else {
            throw SearchIndexError.invalidDocument(document.id)
        }
        records[document.id] = IndexedSearchDocument(document)
    }

    public mutating func remove(id: SearchDocumentID) {
        records.removeValue(forKey: id)
    }

    /// Makes one entity kind exactly match the supplied records, preventing stale
    /// Spotlight-style documents when profiles, groups, or items are removed.
    public mutating func synchronize(
        kind: SearchDocumentKind,
        documents: [SearchDocument]
    ) throws {
        let replacementIDs = Set(documents.map(\.id))
        guard replacementIDs.count == documents.count else {
            let duplicate = documents.map(\.id).first { id in
                documents.count(where: { $0.id == id }) > 1
            } ?? SearchDocumentID("")
            throw SearchIndexError.duplicateIdentifier(duplicate)
        }
        guard documents.allSatisfy({ $0.kind == kind && $0.isValid }) else {
            let invalid = documents.first(where: { $0.kind != kind || !$0.isValid })
            throw SearchIndexError.invalidDocument(invalid?.id ?? SearchDocumentID(""))
        }

        records = records.filter { $0.value.document.kind != kind || replacementIDs.contains($0.key) }
        for document in documents {
            records[document.id] = IndexedSearchDocument(document)
        }
    }

    public func search(
        _ query: String,
        limit: Int = 20,
        now: Date = Date()
    ) -> [SearchResult] {
        let normalizedQuery = SearchText.normalize(query)
        let terms = SearchText.queryTerms(query)
        guard !normalizedQuery.isEmpty, !terms.isEmpty, limit > 0 else { return [] }

        var similarityCache = [SimilarityKey: Double]()
        return records.values.compactMap { record -> ScoredResult? in
            guard let result = score(
                record,
                normalizedQuery: normalizedQuery,
                terms: terms,
                now: now,
                similarityCache: &similarityCache
            ) else {
                return nil
            }
            return ScoredResult(result: result, normalizedTitle: record.title)
        }
        .sorted { lhs, rhs in
            if lhs.result.score != rhs.result.score {
                return lhs.result.score > rhs.result.score
            }
            if lhs.normalizedTitle != rhs.normalizedTitle {
                return lhs.normalizedTitle < rhs.normalizedTitle
            }
            return lhs.result.document.id.value < rhs.result.document.id.value
        }
        .prefix(limit)
        .map(\.result)
    }

    private func score(
        _ record: IndexedSearchDocument,
        normalizedQuery: String,
        terms: [String],
        now: Date,
        similarityCache: inout [SimilarityKey: Double]
    ) -> SearchResult? {
        var score = 0.0
        var reasons = Set<SearchMatchReason>()
        var matchedTerms = 0

        if record.title == normalizedQuery {
            score += 140
            reasons.insert(.exactTitle)
        }
        if record.aliases.contains(normalizedQuery) {
            score += 150
            reasons.insert(.exactAlias)
        }

        for term in terms {
            let expanded = synonymMap.expandedTerms(for: term)
            var best: FieldMatch?
            for candidate in expanded.sorted() {
                if let match = record.bestMatch(
                    for: candidate,
                    originalTerm: term,
                    similarityCache: &similarityCache
                ) {
                    if let currentBest = best {
                        let isBetterScore = match.score > currentBest.score
                        let isPreferredTie = match.score == currentBest.score
                            && match.matchedTerm == term
                            && currentBest.matchedTerm != term
                        if isBetterScore || isPreferredTie {
                            best = match
                        }
                    } else {
                        best = match
                    }
                }
            }
            if let best {
                score += best.score
                reasons.insert(best.reason)
                matchedTerms += 1
                if best.matchedTerm != term {
                    reasons.insert(.synonym)
                }
            }
        }

        guard matchedTerms > 0 else { return nil }
        let coverage = Double(matchedTerms) / Double(terms.count)
        score *= 0.35 + (0.65 * coverage)

        if let lastUsedAt = record.document.lastUsedAt, lastUsedAt <= now {
            let age = now.timeIntervalSince(lastUsedAt)
            let recency = 15 * exp(-age / (7 * 24 * 60 * 60))
            if recency >= 0.25 {
                score += recency
                reasons.insert(.recentUse)
            }
        }

        return SearchResult(document: record.document, score: score, reasons: reasons)
    }
}

private struct IndexedSearchDocument: Sendable {
    let document: SearchDocument
    let title: String
    let aliases: Set<String>
    let fields: [IndexedField]

    init(_ document: SearchDocument) {
        self.document = document
        title = SearchText.normalize(document.title)
        aliases = Set(document.aliases.map(SearchText.normalize))
        fields = [
            IndexedField(values: [document.title], reason: .exactTitle, weight: 42),
            IndexedField(values: document.aliases, reason: .exactAlias, weight: 48),
            IndexedField(values: document.owningApplication.map { [$0] } ?? [], reason: .owningApplication, weight: 34),
            IndexedField(values: document.bundleIdentifier.map { [$0] } ?? [], reason: .bundleIdentifier, weight: 30),
            IndexedField(values: document.groups, reason: .group, weight: 28),
            IndexedField(values: document.profileMemberships, reason: .profileMembership, weight: 26),
            IndexedField(values: document.synonyms, reason: .synonym, weight: 31),
            IndexedField(values: document.keywords, reason: .keyword, weight: 24),
        ].filter { !$0.values.isEmpty }
    }

    func bestMatch(
        for term: String,
        originalTerm: String,
        similarityCache: inout [SimilarityKey: Double]
    ) -> FieldMatch? {
        var best: FieldMatch?
        for field in fields {
            guard let match = field.match(
                term,
                originalTerm: originalTerm,
                similarityCache: &similarityCache
            ) else {
                continue
            }
            if let bestMatch = best, match.score <= bestMatch.score {
                continue
            } else {
                best = match
            }
        }
        return best
    }
}

private struct IndexedField: Sendable {
    let values: [String]
    let tokens: Set<String>
    let reason: SearchMatchReason
    let weight: Double

    init(values: [String], reason: SearchMatchReason, weight: Double) {
        self.values = values.map(SearchText.normalize).filter { !$0.isEmpty }
        tokens = Set(self.values.flatMap { $0.split(separator: " ").map(String.init) })
        self.reason = reason
        self.weight = weight
    }

    func match(
        _ term: String,
        originalTerm _: String,
        similarityCache: inout [SimilarityKey: Double]
    ) -> FieldMatch? {
        if values.contains(term) || tokens.contains(term) {
            return FieldMatch(score: weight + 38, reason: reason, matchedTerm: term)
        }
        if values.contains(where: { $0.hasPrefix(term) }) || tokens.contains(where: { $0.hasPrefix(term) }) {
            return FieldMatch(score: weight + 24, reason: .prefix, matchedTerm: term)
        }
        if values.contains(where: { $0.contains(term) }) {
            return FieldMatch(score: weight + 14, reason: reason, matchedTerm: term)
        }

        guard term.count >= 3 else { return nil }
        let candidates = tokens.filter { abs($0.count - term.count) <= max(2, term.count / 3) }
        let similarity = candidates.map { candidate in
            let key = SimilarityKey(term: term, candidate: candidate)
            if let cached = similarityCache[key] {
                return cached
            }
            let value = SearchDistance.similarity(term, candidate)
            similarityCache[key] = value
            return value
        }.max() ?? 0
        guard similarity >= 0.67 else { return nil }
        return FieldMatch(score: weight + (similarity * 15), reason: .fuzzy, matchedTerm: term)
    }
}

private struct FieldMatch: Sendable {
    let score: Double
    let reason: SearchMatchReason
    let matchedTerm: String
}

private struct ScoredResult {
    let result: SearchResult
    let normalizedTitle: String
}

private struct SimilarityKey: Hashable {
    let term: String
    let candidate: String
}

private enum SearchDistance {
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty || !right.isEmpty else { return 1 }

        var previous = Array(0 ... right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return 1 - (Double(previous[right.count]) / Double(max(left.count, right.count)))
    }
}
