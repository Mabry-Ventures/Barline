//
//  MenuBarCommandValidationTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Typed model-command authority")
struct MenuBarCommandValidationTests {
    @Test("Public command authority comes only from validated coordinator state")
    func coordinatorAuthority() async throws {
        let fixture = CommandFixture()
        let backend = CommandAuthorityBackend(snapshot: fixture.snapshot)
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )

        await #expect(throws: MenuBarCommandAuthorityError.noValidatedSnapshot) {
            try await MenuBarCommandAuthority.current(from: coordinator, now: fixture.now)
        }

        _ = try await coordinator.refresh(now: fixture.now)
        let authority = try await MenuBarCommandAuthority.current(
            from: coordinator,
            availableProfileIDs: [fixture.profileID],
            now: fixture.now
        )
        #expect(authority.expectedGeneration == fixture.snapshot.generation)
        #expect(authority.validatedSnapshot == fixture.snapshot)
    }

    @Test("A valid single reveal is immediate and generation bound")
    func reveal() throws {
        let fixture = CommandFixture()
        let command = MenuBarCommand(
            operation: .reveal,
            targetItemIDs: [fixture.firstID],
            confidence: 0.9
        )

        let result = try fixture.validator.validate(command, authority: fixture.authority).get()

        #expect(result.operation == .reveal)
        #expect(result.authorityGeneration == fixture.snapshot.generation)
        #expect(result.confirmation == .immediate)
    }

    @Test("Low, NaN, and out-of-range confidence cannot produce authority")
    func confidence() {
        let fixture = CommandFixture()
        for confidence in [0.2, Double.nan, -0.1, 1.1] {
            let command = MenuBarCommand(
                operation: .reveal,
                targetItemIDs: [fixture.firstID],
                confidence: confidence
            )
            let result = fixture.validator.validate(command, authority: fixture.authority)
            if confidence == 0.2 {
                #expect(result == .failure(.lowConfidenceRequiresSearch))
            } else {
                #expect(result == .failure(.invalidConfidence))
            }
        }
    }

    @Test("Stale generation and unavailable item IDs are rejected")
    func snapshotAuthority() {
        let fixture = CommandFixture()
        let command = MenuBarCommand(
            operation: .reveal,
            targetItemIDs: [fixture.firstID],
            confidence: 0.9
        )
        let staleAuthority = MenuBarCommandAuthority(
            validatedSnapshot: fixture.snapshot,
            expectedGeneration: fixture.snapshot.generation + 1,
            now: fixture.now
        )
        #expect(
            fixture.validator.validate(command, authority: staleAuthority)
                == .failure(.staleSnapshot(expected: 8, actual: 7))
        )

        let unknown = MenuBarItemID(
            bundleIdentifier: "com.example.missing",
            accessibilityIdentifier: "missing"
        )
        let unavailable = MenuBarCommand(operation: .reveal, targetItemIDs: [unknown], confidence: 0.9)
        #expect(
            fixture.validator.validate(unavailable, authority: fixture.authority)
                == .failure(.staleOrUnavailableItem(unknown))
        )
    }

    @Test("The authority snapshot is independently checked for validity")
    func invalidAuthoritySnapshot() {
        let fixture = CommandFixture()
        let staleSnapshot = MenuBarSnapshot(
            generation: 7,
            capturedAt: fixture.now.addingTimeInterval(-60),
            items: fixture.snapshot.items,
            displayIDs: fixture.snapshot.displayIDs,
            activeSpaceIsValid: true
        )
        let authority = MenuBarCommandAuthority(
            validatedSnapshot: staleSnapshot,
            expectedGeneration: 7,
            now: fixture.now
        )
        let command = MenuBarCommand(
            operation: .reveal,
            targetItemIDs: [fixture.firstID],
            confidence: 0.9
        )

        #expect(
            fixture.validator.validate(command, authority: authority)
                == .failure(.snapshotRejected(.staleSnapshot))
        )
    }

    @Test("Operation shapes enforce bounded targets and profile-only addressing")
    func operationShapes() {
        let fixture = CommandFixture()
        let noTargets = MenuBarCommand(operation: .hide, confidence: 0.9)
        #expect(
            fixture.validator.validate(noTargets, authority: fixture.authority)
                == .failure(.missingItemTargets)
        )

        let duplicate = MenuBarCommand(
            operation: .show,
            targetItemIDs: [fixture.firstID, fixture.firstID],
            confidence: 0.9
        )
        #expect(
            fixture.validator.validate(duplicate, authority: fixture.authority)
                == .failure(.duplicateItemTarget(fixture.firstID))
        )

        let oneItemGroup = MenuBarCommand(
            operation: .group,
            targetItemIDs: [fixture.firstID],
            confidence: 0.9
        )
        #expect(
            fixture.validator.validate(oneItemGroup, authority: fixture.authority)
                == .failure(.operationRequiresMultipleItems(.group))
        )

        let missingProfile = MenuBarCommand(operation: .activateProfile, confidence: 0.9)
        #expect(
            fixture.validator.validate(missingProfile, authority: fixture.authority)
                == .failure(.missingProfileTarget)
        )
    }

    @Test("Bulk and destructive commands always require a preview")
    func confirmationPolicy() throws {
        let fixture = CommandFixture()
        let hide = MenuBarCommand(
            operation: .hide,
            targetItemIDs: [fixture.firstID, fixture.secondID],
            confidence: 0.9
        )
        let hideResult = try fixture.validator.validate(hide, authority: fixture.authority).get()
        #expect(hideResult.confirmation == .previewRequired(.bulkHide(itemCount: 2)))

        let replace = MenuBarCommand(
            operation: .replaceWithProfile,
            targetProfileID: fixture.profileID,
            confidence: 0.9
        )
        let replaceResult = try fixture.validator.validate(replace, authority: fixture.authority).get()
        #expect(
            replaceResult.confirmation
                == .previewRequired(.profileReplacement(fixture.profileID))
        )
    }

    @Test("Unavailable profiles and active menu tracking reject mutation")
    func profileAndTrackingSafety() {
        let fixture = CommandFixture()
        let missing = ProfileID("missing")
        let profile = MenuBarCommand(
            operation: .activateProfile,
            targetProfileID: missing,
            confidence: 0.9
        )
        #expect(
            fixture.validator.validate(profile, authority: fixture.authority)
                == .failure(.staleOrUnavailableProfile(missing))
        )

        let trackingSnapshot = MenuBarSnapshot(
            generation: fixture.snapshot.generation,
            capturedAt: fixture.now,
            items: fixture.snapshot.items,
            displayIDs: fixture.snapshot.displayIDs,
            activeSpaceIsValid: true,
            menuTrackingIsActive: true
        )
        let tracking = MenuBarCommandAuthority(
            validatedSnapshot: trackingSnapshot,
            expectedGeneration: trackingSnapshot.generation,
            now: fixture.now
        )
        let reveal = MenuBarCommand(
            operation: .reveal,
            targetItemIDs: [fixture.firstID],
            confidence: 0.9
        )
        #expect(
            fixture.validator.validate(reveal, authority: tracking)
                == .failure(.menuTrackingActive)
        )
    }
}

private actor CommandAuthorityBackend: MenuBarBackend {
    let capabilities = MenuBarCapabilities(
        canSnapshot: true,
        canMove: false,
        canReveal: false,
        canActivate: false,
        canRestore: false
    )
    private let value: MenuBarSnapshot

    init(snapshot: MenuBarSnapshot) {
        value = snapshot
    }

    func snapshot() -> MenuBarSnapshot {
        value
    }

    func move(_: MenuBarMoveOperation) throws -> MenuBarMutationResult {
        throw MenuBarBackendError.unavailableCapability("move")
    }

    func reveal(_: MenuBarItemID) throws -> MenuBarMutationResult {
        throw MenuBarBackendError.unavailableCapability("reveal")
    }

    func activate(_: MenuBarItemID, button _: MenuBarMouseButton) throws {
        throw MenuBarBackendError.unavailableCapability("activate")
    }

    func restore(_: MenuBarSnapshot) throws -> MenuBarMutationResult {
        throw MenuBarBackendError.unavailableCapability("restore")
    }

    func health() -> MenuBarBackendHealth {
        MenuBarBackendHealth(backendName: "CommandAuthorityTest", state: .healthy)
    }

    func restart() {}
}

private struct CommandFixture {
    let now = Date(timeIntervalSince1970: 10000)
    let firstID = MenuBarItemID(
        bundleIdentifier: "com.example.first",
        accessibilityIdentifier: "first"
    )
    let secondID = MenuBarItemID(
        bundleIdentifier: "com.example.second",
        accessibilityIdentifier: "second"
    )
    let profileID = ProfileID("presentation")
    let snapshot: MenuBarSnapshot
    let authority: MenuBarCommandAuthority
    let validator = MenuBarCommandValidator()

    init() {
        let display = MenuBarDisplayID("display")
        snapshot = MenuBarSnapshot(
            generation: 7,
            capturedAt: now,
            items: [
                MenuBarItemDescriptor(id: firstID, section: .visible, order: 0, displayID: display),
                MenuBarItemDescriptor(id: secondID, section: .visible, order: 1, displayID: display),
            ],
            displayIDs: [display],
            activeSpaceIsValid: true
        )
        authority = MenuBarCommandAuthority(
            validatedSnapshot: snapshot,
            expectedGeneration: snapshot.generation,
            availableProfileIDs: [profileID],
            now: now
        )
    }
}
