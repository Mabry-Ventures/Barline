//
//  SearchAvailability.swift
//  Barline
//

import Foundation

public enum SearchCapabilityUnavailableReason: String, Codable, CaseIterable, Sendable {
    case disabled
    case modelNotReady
    case unsupportedHardware
    case unsupportedRegion
    case unsupportedLanguage
    case unsupportedOperatingSystem
    case apiUnavailable
}

public enum SearchCapabilityAvailability: Codable, Equatable, Sendable {
    case available
    case unavailable(SearchCapabilityUnavailableReason)

    public var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
}

public struct SearchAvailability: Codable, Equatable, Sendable {
    public var deterministicLocal: SearchCapabilityAvailability {
        .available
    }

    public let coreSpotlight: SearchCapabilityAvailability
    public let foundationModels: SearchCapabilityAvailability
    public let spotlightSearchTool: SearchCapabilityAvailability

    public init(
        coreSpotlight: SearchCapabilityAvailability,
        foundationModels: SearchCapabilityAvailability,
        spotlightSearchTool: SearchCapabilityAvailability
    ) {
        self.coreSpotlight = coreSpotlight
        self.foundationModels = foundationModels
        self.spotlightSearchTool = spotlightSearchTool
    }

    public static let deterministicOnly = SearchAvailability(
        coreSpotlight: .unavailable(.apiUnavailable),
        foundationModels: .unavailable(.apiUnavailable),
        spotlightSearchTool: .unavailable(.unsupportedOperatingSystem)
    )

    public func plan(for request: SearchRequestClassification) -> SearchExecutionPlan {
        SearchExecutionPlan(
            runDeterministicLocal: true,
            queryCoreSpotlight: coreSpotlight.isAvailable,
            useFoundationModels: request == .ambiguousNaturalLanguage && foundationModels.isAvailable,
            provideSpotlightSearchTool: request == .ambiguousNaturalLanguage
                && foundationModels.isAvailable
                && spotlightSearchTool.isAvailable
        )
    }
}

public enum SearchRequestClassification: String, Codable, Sendable {
    case ordinary
    case ambiguousNaturalLanguage
}

public struct SearchExecutionPlan: Codable, Equatable, Sendable {
    public let runDeterministicLocal: Bool
    public let queryCoreSpotlight: Bool
    public let useFoundationModels: Bool
    public let provideSpotlightSearchTool: Bool

    public init(
        runDeterministicLocal: Bool,
        queryCoreSpotlight: Bool,
        useFoundationModels: Bool,
        provideSpotlightSearchTool: Bool
    ) {
        self.runDeterministicLocal = runDeterministicLocal
        self.queryCoreSpotlight = queryCoreSpotlight
        self.useFoundationModels = useFoundationModels
        self.provideSpotlightSearchTool = provideSpotlightSearchTool
    }
}
