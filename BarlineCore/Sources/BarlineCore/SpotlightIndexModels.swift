//
//  SpotlightIndexModels.swift
//  Barline
//

import Foundation

public enum SpotlightIndexRecordError: Error, Equatable, Sendable {
    case invalidDocument(SearchDocumentID)
    case malformedUniqueIdentifier(String)
}

/// Platform-neutral input for a Core Spotlight adapter. Its closed field set
/// prevents screen content, paths, window references, and process inventories
/// from leaking into the system index through arbitrary metadata.
public struct SpotlightIndexRecord: Codable, Equatable, Sendable {
    public static let domainIdentifier = "com.mabryventures.barline.search"
    private static let identifierPrefix = "barline.search"

    public let uniqueIdentifier: String
    public let domainIdentifier: String
    public let documentID: SearchDocumentID
    public let kind: SearchDocumentKind
    public let title: String
    public let keywords: [String]

    public init(document: SearchDocument) throws {
        guard document.isValid else {
            throw SpotlightIndexRecordError.invalidDocument(document.id)
        }

        uniqueIdentifier = Self.uniqueIdentifier(for: document.id, kind: document.kind)
        domainIdentifier = Self.domainIdentifier
        documentID = document.id
        kind = document.kind
        title = String(document.title.prefix(256))
        keywords = Self.makeKeywords(from: document)
    }

    public static func uniqueIdentifier(
        for documentID: SearchDocumentID,
        kind: SearchDocumentKind
    ) -> String {
        "\(identifierPrefix).\(kind.rawValue).\(documentID.value)"
    }

    public static func documentID(
        fromUniqueIdentifier identifier: String
    ) throws -> SearchDocumentID {
        for kind in SearchDocumentKind.allCases {
            let prefix = "\(identifierPrefix).\(kind.rawValue)."
            guard identifier.hasPrefix(prefix) else { continue }
            let documentID = SearchDocumentID(String(identifier.dropFirst(prefix.count)))
            guard documentID.isValid else {
                throw SpotlightIndexRecordError.malformedUniqueIdentifier(identifier)
            }
            return documentID
        }
        throw SpotlightIndexRecordError.malformedUniqueIdentifier(identifier)
    }

    private static func makeKeywords(from document: SearchDocument) -> [String] {
        let candidates = [
            document.owningApplication,
            document.bundleIdentifier,
        ].compactMap(\.self) + document.aliases + document.groups
            + document.profileMemberships + document.synonyms + document.keywords

        var seen = Set<String>()
        return candidates.compactMap { value -> String? in
            let bounded = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
            let identity = bounded.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard !bounded.isEmpty, seen.insert(identity).inserted else { return nil }
            return bounded
        }
        .prefix(64)
        .map(\.self)
    }
}
