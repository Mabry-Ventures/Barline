//
//  SearchCommandResolutionTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Model command resolution and evaluations")
struct SearchCommandResolutionTests {
    @Test("Candidate IDs resolve only through the supplied context")
    func resolvesContext() throws {
        let fixture = SearchResolutionFixture()
        let candidate = SearchCommandCandidate(
            operation: .reveal,
            targetDocumentIDs: [fixture.item.id],
            confidence: 0.9
        )

        let command = try fixture.resolver.resolve(candidate, against: fixture.documents).get()

        #expect(command.targetItemIDs == [fixture.itemID])
        #expect(command.targetProfileID == nil)
    }

    @Test("Hallucinated, duplicate, and wrong-kind IDs fail closed")
    func rejectsInvalidIDs() {
        let fixture = SearchResolutionFixture()
        let unknownID = SearchDocumentID("missing")
        let unknown = SearchCommandCandidate(
            operation: .reveal,
            targetDocumentIDs: [unknownID],
            confidence: 0.9
        )
        #expect(
            fixture.resolver.resolve(unknown, against: fixture.documents)
                == .failure(.unknownTarget(unknownID))
        )

        let duplicate = SearchCommandCandidate(
            operation: .show,
            targetDocumentIDs: [fixture.item.id, fixture.item.id],
            confidence: 0.9
        )
        #expect(
            fixture.resolver.resolve(duplicate, against: fixture.documents)
                == .failure(.duplicateTarget(fixture.item.id))
        )

        let wrongKind = SearchCommandCandidate(
            operation: .reveal,
            targetDocumentIDs: [fixture.profile.id],
            confidence: 0.9
        )
        #expect(
            fixture.resolver.resolve(wrongKind, against: fixture.documents)
                == .failure(.targetIsNotMenuBarItem(fixture.profile.id))
        )
    }

    @Test("Invalid and oversized context fails before candidate resolution")
    func rejectsInvalidContext() {
        let fixture = SearchResolutionFixture()
        let candidate = SearchCommandCandidate(operation: .reveal, confidence: 0.9)
        let invalid = SearchDocument(
            id: .init(""),
            kind: .help,
            entity: .help(.init("help")),
            title: "Help"
        )
        #expect(
            fixture.resolver.resolve(candidate, against: [invalid])
                == .failure(.invalidContextDocument(.init("")))
        )

        let boundedResolver = SearchCommandResolver(maximumContextDocuments: 1)
        #expect(
            boundedResolver.resolve(candidate, against: fixture.documents)
                == .failure(.tooManyContextDocuments(maximum: 1, actual: 2))
        )
    }

    @Test("Profile targets resolve separately from item targets")
    func resolvesProfile() throws {
        let fixture = SearchResolutionFixture()
        let candidate = SearchCommandCandidate(
            operation: .activateProfile,
            targetProfileDocumentID: fixture.profile.id,
            confidence: 0.95
        )

        let command = try fixture.resolver.resolve(candidate, against: fixture.documents).get()

        #expect(command.targetItemIDs.isEmpty)
        #expect(command.targetProfileID == fixture.profileID)
    }

    @Test("Routing keeps exact search local and sends natural commands to interpretation")
    func routing() {
        let fixture = SearchResolutionFixture()
        let exact = SearchResult(document: fixture.item, score: 100, reasons: [.exactTitle])
        let fuzzy = SearchResult(document: fixture.item, score: 20, reasons: [.fuzzy])
        let policy = SearchCommandRoutingPolicy()

        #expect(!policy.shouldInterpret(query: "Display", deterministicResults: [exact]))
        #expect(policy.shouldInterpret(query: "Hide everything except Display", deterministicResults: [fuzzy]))
        #expect(!policy.shouldInterpret(query: "disp", deterministicResults: [fuzzy]))
    }

    @Test("Evaluation thresholds require every unsafe request to be rejected")
    func evaluationThresholds() {
        let corpus = SearchEvaluationCorpus.representative
        let perfect = Dictionary(uniqueKeysWithValues: corpus.map { ($0.name, $0.expectation) })
        #expect(SearchEvaluationRunner.evaluate(corpus: corpus, predictions: perfect).passes)

        var unsafeFailure = perfect
        unsafeFailure["malicious"] = .searchFallback
        let report = SearchEvaluationRunner.evaluate(corpus: corpus, predictions: unsafeFailure)
        #expect(!report.passes)
        #expect(report.unsafeRejectionRate == 0.5)
    }

    @Test("Execution policy exposes only commands with complete bounded semantics")
    func executionDisposition() throws {
        let fixture = SearchResolutionFixture()
        let immediate = try fixture.validatedCommand(
            operation: .show,
            itemIDs: [fixture.itemID]
        )
        #expect(
            SearchCommandExecutionPolicy().disposition(for: immediate)
                == .executableImmediately
        )

        let bulk = try fixture.validatedCommand(
            operation: .hide,
            itemIDs: [fixture.itemID, fixture.secondItemID]
        )
        #expect(
            SearchCommandExecutionPolicy().disposition(for: bulk)
                == .nonRunnable(.atomicBatchMutationUnavailable)
        )

        let rearrange = try fixture.validatedCommand(
            operation: .rearrange,
            itemIDs: [fixture.itemID]
        )
        #expect(
            SearchCommandExecutionPolicy().disposition(for: rearrange)
                == .nonRunnable(.missingArrangementDestination)
        )

        let replace = try fixture.validatedCommand(
            operation: .replaceWithProfile,
            profileID: fixture.profileID
        )
        #expect(
            SearchCommandExecutionPolicy().disposition(for: replace)
                == .explicitConfirmationRequired
        )
    }
}

private struct SearchResolutionFixture {
    let itemID = MenuBarItemID(
        bundleIdentifier: "com.example.display",
        accessibilityIdentifier: "display"
    )
    let secondItemID = MenuBarItemID(
        bundleIdentifier: "com.example.clock",
        accessibilityIdentifier: "clock"
    )
    let profileID = ProfileID("presentation")
    let item: SearchDocument
    let profile: SearchDocument
    let resolver = SearchCommandResolver()

    var documents: [SearchDocument] {
        [item, profile]
    }

    init() {
        item = SearchDocument(
            id: .init("item.display"),
            kind: .menuBarItem,
            entity: .menuBarItem(itemID),
            title: "Display"
        )
        profile = SearchDocument(
            id: .init("profile.presentation"),
            kind: .profile,
            entity: .profile(profileID),
            title: "Presentation"
        )
    }

    func validatedCommand(
        operation: MenuBarCommandOperation,
        itemIDs: [MenuBarItemID] = [],
        profileID: ProfileID? = nil
    ) throws -> ValidatedMenuBarCommand {
        let displayID = MenuBarDisplayID("display")
        let snapshot = MenuBarSnapshot(
            generation: 1,
            capturedAt: Date(timeIntervalSince1970: 1000),
            items: [itemID, secondItemID].enumerated().map { index, itemID in
                MenuBarItemDescriptor(
                    id: itemID,
                    section: .visible,
                    order: index,
                    displayID: displayID
                )
            },
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
        let authority = MenuBarCommandAuthority(
            validatedSnapshot: snapshot,
            expectedGeneration: 1,
            availableProfileIDs: [self.profileID],
            now: snapshot.capturedAt
        )
        return try MenuBarCommandValidator().validate(
            MenuBarCommand(
                operation: operation,
                targetItemIDs: itemIDs,
                targetProfileID: profileID,
                confidence: 0.95
            ),
            authority: authority
        ).get()
    }
}
