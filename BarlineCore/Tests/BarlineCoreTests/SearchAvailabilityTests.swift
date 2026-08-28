//
//  SearchAvailabilityTests.swift
//  Barline
//

@testable import BarlineCore
import Testing

@Suite("Search availability and evaluation corpus")
struct SearchAvailabilityTests {
    @Test("Deterministic search remains enabled when every optional capability is unavailable")
    func deterministicFallback() {
        let plan = SearchAvailability.deterministicOnly.plan(for: .ambiguousNaturalLanguage)

        #expect(plan.runDeterministicLocal)
        #expect(!plan.queryCoreSpotlight)
        #expect(!plan.useFoundationModels)
        #expect(!plan.provideSpotlightSearchTool)
    }

    @Test("Model and Spotlight tool are used only for ambiguous local requests")
    func optionalStages() {
        let availability = SearchAvailability(
            coreSpotlight: .available,
            foundationModels: .available,
            spotlightSearchTool: .available
        )

        let ordinary = availability.plan(for: .ordinary)
        #expect(ordinary.runDeterministicLocal)
        #expect(ordinary.queryCoreSpotlight)
        #expect(!ordinary.useFoundationModels)
        #expect(!ordinary.provideSpotlightSearchTool)

        let ambiguous = availability.plan(for: .ambiguousNaturalLanguage)
        #expect(ambiguous.useFoundationModels)
        #expect(ambiguous.provideSpotlightSearchTool)
    }

    @Test("Spotlight tool cannot be exposed without a ready local model")
    func toolRequiresModel() {
        let availability = SearchAvailability(
            coreSpotlight: .available,
            foundationModels: .unavailable(.modelNotReady),
            spotlightSearchTool: .available
        )

        let plan = availability.plan(for: .ambiguousNaturalLanguage)
        #expect(!plan.useFoundationModels)
        #expect(!plan.provideSpotlightSearchTool)
    }

    @Test("Privacy-safe corpus covers all required outcome classes")
    func evaluationCorpus() {
        let corpus = SearchEvaluationCorpus.representative
        #expect(Set(corpus.map(\.name)).count == corpus.count)
        #expect(corpus.contains { $0.name == "exact item" })
        #expect(corpus.contains { $0.name == "synonym" })
        #expect(corpus.contains { $0.name == "owning app" })
        #expect(corpus.contains { $0.name == "profile switch" })
        #expect(corpus.contains { $0.name == "presentation" })
        #expect(corpus.contains { $0.expectation == .searchFallback })
        #expect(corpus.filter { $0.expectation == .rejection }.count >= 2)
    }
}
