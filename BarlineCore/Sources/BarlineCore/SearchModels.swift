//
//  SearchModels.swift
//  Barline
//

import Foundation

public struct SearchDocumentID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var description: String {
        value
    }

    public var isValid: Bool {
        !value.isEmpty
    }
}

public struct ProfileID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = SearchText.normalize(value)
    }

    public var description: String {
        value
    }

    public var isValid: Bool {
        !value.isEmpty
    }
}

public struct GroupID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = SearchText.normalize(value)
    }

    public var description: String {
        value
    }

    public var isValid: Bool {
        !value.isEmpty
    }
}

public struct BarlineCommandID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = SearchText.normalize(value)
    }

    public var description: String {
        value
    }
}

public struct BarlineHelpActionID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = SearchText.normalize(value)
    }

    public var description: String {
        value
    }
}

public enum SearchEntityReference: Codable, Hashable, Sendable {
    case menuBarItem(MenuBarItemID)
    case profile(ProfileID)
    case group(GroupID)
    case command(BarlineCommandID)
    case help(BarlineHelpActionID)
}

public enum SearchDocumentKind: String, Codable, CaseIterable, Sendable {
    case menuBarItem
    case profile
    case group
    case command
    case help
}

/// A privacy-bounded search record. It intentionally has no path, window, image,
/// process-inventory, or arbitrary metadata field.
public struct SearchDocument: Codable, Hashable, Sendable {
    public let id: SearchDocumentID
    public let kind: SearchDocumentKind
    public let entity: SearchEntityReference
    public let title: String
    public let owningApplication: String?
    public let bundleIdentifier: String?
    public let aliases: [String]
    public let groups: [String]
    public let profileMemberships: [String]
    public let synonyms: [String]
    public let keywords: [String]
    public let lastUsedAt: Date?

    public init(
        id: SearchDocumentID,
        kind: SearchDocumentKind,
        entity: SearchEntityReference,
        title: String,
        owningApplication: String? = nil,
        bundleIdentifier: String? = nil,
        aliases: [String] = [],
        groups: [String] = [],
        profileMemberships: [String] = [],
        synonyms: [String] = [],
        keywords: [String] = [],
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.entity = entity
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.owningApplication = owningApplication?.nilIfBlank
        self.bundleIdentifier = bundleIdentifier?.nilIfBlank
        self.aliases = aliases.nonBlankUniqueValues
        self.groups = groups.nonBlankUniqueValues
        self.profileMemberships = profileMemberships.nonBlankUniqueValues
        self.synonyms = synonyms.nonBlankUniqueValues
        self.keywords = keywords.nonBlankUniqueValues
        self.lastUsedAt = lastUsedAt
    }

    public var isValid: Bool {
        id.isValid && !title.isEmpty && entity.kind == kind
    }
}

public extension SearchEntityReference {
    var kind: SearchDocumentKind {
        switch self {
        case .menuBarItem: .menuBarItem
        case .profile: .profile
        case .group: .group
        case .command: .command
        case .help: .help
        }
    }
}

public enum SearchMatchReason: String, Codable, CaseIterable, Sendable {
    case exactTitle
    case exactAlias
    case prefix
    case fuzzy
    case owningApplication
    case bundleIdentifier
    case group
    case profileMembership
    case synonym
    case keyword
    case recentUse
}

public struct SearchResult: Codable, Equatable, Sendable {
    public let document: SearchDocument
    public let score: Double
    public let reasons: Set<SearchMatchReason>

    public init(document: SearchDocument, score: Double, reasons: Set<SearchMatchReason>) {
        self.document = document
        self.score = score
        self.reasons = reasons
    }
}

public struct SearchSynonymMap: Codable, Equatable, Sendable {
    private let expansions: [String: Set<String>]

    public init(groups: [[String]]) {
        var result = [String: Set<String>]()
        for group in groups {
            let normalized = Set(group.map(SearchText.normalize).filter { !$0.isEmpty })
            for term in normalized {
                result[term, default: []].formUnion(normalized.subtracting([term]))
            }
        }
        expansions = result
    }

    public func expandedTerms(for term: String) -> Set<String> {
        let normalized = SearchText.normalize(term)
        return Set([normalized]).union(expansions[normalized] ?? [])
    }

    public static let curated = SearchSynonymMap(groups: [
        ["wi-fi", "wifi", "wireless", "network"],
        ["battery", "power", "charge"],
        ["clock", "time"],
        ["display", "monitor", "screen"],
        ["audio", "sound", "volume"],
        ["cloud", "sync", "storage"],
        ["hide", "conceal"],
        ["show", "reveal", "find"],
        ["presentation", "presenting", "meeting"],
    ])
}

enum SearchText {
    static let stopWords: Set<String> = [
        "a", "an", "and", "app", "for", "i", "is", "me", "my", "of", "please",
        "that", "the", "to", "where", "with",
    ]

    static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." ? Character(scalar) : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func queryTerms(_ value: String) -> [String] {
        let all = normalize(value).split(separator: " ").map(String.init)
        let meaningful = all.filter { !stopWords.contains($0) }
        return meaningful.isEmpty ? all : meaningful
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension [String] {
    var nonBlankUniqueValues: [String] {
        var seen = Set<String>()
        return compactMap(\.nilIfBlank).filter { seen.insert(SearchText.normalize($0)).inserted }
    }
}
