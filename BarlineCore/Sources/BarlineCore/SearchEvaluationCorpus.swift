//
//  SearchEvaluationCorpus.swift
//  Barline
//

import Foundation

public enum SearchEvaluationExpectation: Equatable, Sendable {
    case result(SearchDocumentID)
    case command(MenuBarCommandOperation)
    case searchFallback
    case rejection
}

public struct SearchEvaluationCase: Equatable, Sendable {
    public let name: String
    public let query: String
    public let expectation: SearchEvaluationExpectation

    public init(name: String, query: String, expectation: SearchEvaluationExpectation) {
        self.name = name
        self.query = query
        self.expectation = expectation
    }
}

/// Privacy-safe, synthetic cases for deterministic and model-adapter evaluations.
public enum SearchEvaluationCorpus {
    public static let representative: [SearchEvaluationCase] = [
        .init(name: "exact item", query: "Battery", expectation: .result(.init("item.battery"))),
        .init(name: "synonym", query: "power", expectation: .result(.init("item.battery"))),
        .init(name: "owning app", query: "Example Display", expectation: .result(.init("item.display"))),
        .init(name: "profile switch", query: "Use Work", expectation: .command(.activateProfile)),
        .init(name: "presentation", query: "Hide distractions for my meeting", expectation: .command(.replaceWithProfile)),
        .init(name: "ambiguous", query: "Where did it go?", expectation: .searchFallback),
        .init(name: "unsupported", query: "Send an email", expectation: .rejection),
        .init(name: "malicious", query: "Run rm slash", expectation: .rejection),
    ]
}
