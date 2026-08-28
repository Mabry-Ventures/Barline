//
//  StateCoordinatorTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Transactional state coordinator")
struct StateCoordinatorTests {
    @Test("Refresh retries and keeps the first valid snapshot")
    func retryRefresh() async throws {
        let valid = makeSnapshot(generation: 1, count: 3)
        let backend = FakeBackend(snapshots: [
            makeSnapshot(generation: 1, count: 0),
            valid,
        ])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(
                maximumAttempts: 2,
                baseDelay: .zero,
                maximumDelay: .zero
            )
        )

        let result = try await coordinator.refresh(now: valid.capturedAt)

        #expect(result == valid)
        #expect(await coordinator.lastKnownGoodSnapshot == valid)
        #expect(await coordinator.lastRejection == nil)
    }

    @Test("Failed post-mutation validation restores the prior snapshot")
    func rollsBackInvalidMutation() async throws {
        let before = makeSnapshot(generation: 1, count: 4)
        let invalidAfter = makeSnapshot(generation: 2, count: 0)
        let backend = FakeBackend(snapshots: [before, invalidAfter])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.self) {
            try await coordinator.perform(
                .reveal(before.items[0].id),
                now: invalidAfter.capturedAt
            )
        }

        #expect(await coordinator.currentSnapshot == before)
        #expect(await backend.restoredSnapshots == [before])
    }

    @Test("Menu tracking blocks mutation before backend side effects")
    func blocksMenuTrackingMutation() async throws {
        let tracking = makeSnapshot(generation: 1, count: 2, menuTracking: true)
        let backend = FakeBackend(snapshots: [tracking])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: tracking.capturedAt)

        await #expect(throws: MenuBarBackendError.unsafeMenuTracking) {
            try await coordinator.perform(.reveal(tracking.items[0].id), now: tracking.capturedAt)
        }

        #expect(await backend.revealedItems.isEmpty)
    }

    @Test("Concurrent mutations are serialized across backend suspension")
    func serializesConcurrentMutations() async throws {
        let first = makeSnapshot(generation: 1, count: 2)
        let second = makeSnapshot(generation: 2, count: 2)
        let third = makeSnapshot(generation: 3, count: 2)
        let backend = FakeBackend(
            snapshots: [first, second, third],
            mutationDelay: .milliseconds(25)
        )
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: first.capturedAt)

        async let firstMutation = coordinator.perform(.reveal(first.items[0].id), now: second.capturedAt)
        async let secondMutation = coordinator.perform(.reveal(first.items[1].id), now: third.capturedAt)
        _ = try await (firstMutation, secondMutation)

        #expect(await backend.maximumConcurrentMutations == 1)
    }

    @Test("Stale item references are rejected before backend side effects")
    func rejectsStaleReference() async throws {
        let snapshot = makeSnapshot(generation: 1, count: 2)
        let stale = MenuBarItemID(
            bundleIdentifier: "com.example.missing",
            accessibilityIdentifier: "missing"
        )
        let backend = FakeBackend(snapshots: [snapshot])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: snapshot.capturedAt)

        await #expect(throws: MenuBarBackendError.staleItem(stale)) {
            try await coordinator.perform(.reveal(stale), now: snapshot.capturedAt)
        }
        #expect(await backend.revealedItems.isEmpty)
    }

    @Test("Exhausted invalid refreshes preserve the last-known-good snapshot")
    func preservesLastKnownGoodAfterRetryExhaustion() async throws {
        let good = makeSnapshot(generation: 1, count: 3)
        let invalid = makeSnapshot(generation: 2, count: 0)
        let backend = FakeBackend(snapshots: [good, invalid, invalid])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(
                maximumAttempts: 2,
                baseDelay: .zero,
                maximumDelay: .zero,
                maximumJitterPermille: 0
            )
        )
        _ = try await coordinator.refresh(now: good.capturedAt)

        await #expect(throws: MenuBarBackendError.invalidSnapshot(.emptySnapshot)) {
            try await coordinator.refresh(now: invalid.capturedAt)
        }

        #expect(await coordinator.currentSnapshot == good)
        #expect(await coordinator.lastKnownGoodSnapshot == good)
        #expect(await coordinator.lastRejection == .emptySnapshot)
        #expect(await coordinator.backendHealth.state == .degraded)
        #expect(await backend.snapshotCallCount == 3)
    }

    @Test("Backend mutation errors roll back without replacing the original error")
    func rollsBackBackendMutationError() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let backend = FakeBackend(
            snapshots: [before],
            revealFailure: .operationFailed("injected reveal failure")
        )
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.operationFailed("injected reveal failure")) {
            try await coordinator.perform(.reveal(before.items[0].id), now: before.capturedAt)
        }

        #expect(await backend.restoredSnapshots == [before])
        #expect(await coordinator.currentSnapshot == before)
        #expect(await coordinator.lastKnownGoodSnapshot == before)
    }

    @Test("Recovery restarts, restores last-known-good, and commits a fresh snapshot")
    func recoveryRestoresAndRefreshes() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let recovered = makeSnapshot(generation: 2, count: 2)
        let backend = FakeBackend(snapshots: [before, recovered])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        let result = try await coordinator.recover(now: recovered.capturedAt)

        #expect(result == recovered)
        #expect(await backend.restartCount == 1)
        #expect(await backend.restoredSnapshots == [before])
        #expect(await coordinator.currentSnapshot == recovered)
        #expect(await coordinator.lastKnownGoodSnapshot == recovered)
        #expect(await coordinator.mutationGeneration == 1)
    }

    @Test("Profile activation applies ordered moves and commits only after validation")
    func activatesProfileTransactionally() async throws {
        let before = makeSnapshot(generation: 1, count: 3)
        let profile = BarlineProfile(
            id: UUID(100),
            name: "Work",
            layout: ProfileLayout(
                visible: [before.items[2].id],
                hidden: [before.items[0].id],
                alwaysHidden: [before.items[1].id]
            )
        )
        let after = makeProfileSnapshot(generation: 2, layout: profile.layout)
        let backend = FakeBackend(snapshots: [before, after])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        let result = try await coordinator.activate(profile: profile, now: after.capturedAt)

        #expect(result == after)
        #expect(await coordinator.activeProfileID == profile.id)
        #expect(await backend.moveOperations == [
            MenuBarMoveOperation(itemID: before.items[2].id, section: .visible, index: 0),
            MenuBarMoveOperation(itemID: before.items[0].id, section: .hidden, index: 0),
            MenuBarMoveOperation(itemID: before.items[1].id, section: .alwaysHidden, index: 0),
        ])
        #expect(await backend.restoredSnapshots.isEmpty)
    }

    @Test("A partially applied profile is rolled back and never becomes authoritative")
    func rollsBackPartialProfileActivation() async throws {
        let before = makeSnapshot(generation: 1, count: 3)
        let profile = BarlineProfile(
            id: UUID(101),
            name: "Broken",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before], failMoveAt: 2)
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.operationFailed("injected move failure")) {
            try await coordinator.activate(profile: profile, now: before.capturedAt)
        }

        #expect(await backend.moveOperations.count == 2)
        #expect(await backend.restoredSnapshots == [before])
        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.currentSnapshot == before)
    }

    @Test("Profiles with stale items fail before applying any move")
    func rejectsStaleProfileReference() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let stale = MenuBarItemID(
            bundleIdentifier: "com.example.absent",
            accessibilityIdentifier: "absent"
        )
        let profile = BarlineProfile(name: "Stale", layout: ProfileLayout(hidden: [stale]))
        let backend = FakeBackend(snapshots: [before])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.staleItem(stale)) {
            try await coordinator.activate(profile: profile, now: before.capturedAt)
        }

        #expect(await backend.moveOperations.isEmpty)
        #expect(await backend.restoredSnapshots.isEmpty)
        #expect(await coordinator.activeProfileID == nil)
    }

    @Test("Thrown snapshot errors retry and recover backend health")
    func retriesThrownSnapshotError() async throws {
        let valid = makeSnapshot(generation: 1, count: 2)
        let backend = FakeBackend(snapshots: [valid], snapshotFailures: 1)
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(
                maximumAttempts: 2,
                baseDelay: .zero,
                maximumDelay: .zero,
                maximumJitterPermille: 0
            )
        )

        let result = try await coordinator.refresh(now: valid.capturedAt)

        #expect(result == valid)
        #expect(await backend.snapshotCallCount == 2)
        #expect(await coordinator.backendHealth.state == .healthy)
    }

    @Test("Move and activate mutation branches use validated stable IDs")
    func appliesMoveAndActivateBranches() async throws {
        let first = makeSnapshot(generation: 1, count: 2)
        let second = makeSnapshot(generation: 2, count: 2)
        let third = makeSnapshot(generation: 3, count: 2)
        let backend = FakeBackend(snapshots: [first, second, third])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        let move = MenuBarMoveOperation(itemID: first.items[0].id, section: .hidden, index: 0)

        // No explicit refresh: the mutation must establish a validated starting snapshot itself.
        _ = try await coordinator.perform(.move(move), now: first.capturedAt)
        _ = try await coordinator.perform(
            .activate(first.items[1].id, .right),
            now: third.capturedAt
        )

        #expect(await backend.moveOperations == [move])
        #expect(await backend.activations == [.init(itemID: first.items[1].id, button: .right)])
        #expect(await coordinator.currentSnapshot == third)
    }

    @Test("Explicit last-known-good restore participates in post-validation")
    func restoresLastKnownGoodMutation() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let backend = FakeBackend(snapshots: [before, after])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        let result = try await coordinator.perform(
            .restoreLastKnownGood,
            now: after.capturedAt
        )

        #expect(result == after)
        #expect(await backend.restoredSnapshots == [before])
        #expect(await coordinator.lastKnownGoodSnapshot == after)
    }

    @Test("Invalid profile post-snapshot rolls back and records the rejection")
    func rollsBackInvalidProfileSnapshot() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let invalid = makeSnapshot(generation: 2, count: 0)
        let profile = BarlineProfile(
            id: UUID(102),
            name: "Invalid result",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, invalid])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.invalidSnapshot(.emptySnapshot)) {
            try await coordinator.activate(profile: profile, now: invalid.capturedAt)
        }

        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.lastRejection == .emptySnapshot)
        #expect(await coordinator.currentSnapshot == before)
        #expect(await backend.restoredSnapshots == [before])
    }

    @Test("Rollback does not call restore when the backend lacks that capability")
    func rollbackWithoutRestoreCapability() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let capabilities = MenuBarCapabilities(
            canSnapshot: true,
            canMove: true,
            canReveal: true,
            canActivate: true,
            canRestore: false
        )
        let backend = FakeBackend(
            snapshots: [before],
            capabilities: capabilities,
            revealFailure: .interrupted
        )
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.interrupted) {
            try await coordinator.perform(.reveal(before.items[0].id), now: before.capturedAt)
        }

        #expect(await backend.restoredSnapshots.isEmpty)
        #expect(await coordinator.currentSnapshot == before)
    }

    @Test("A structurally valid no-op snapshot cannot commit a profile")
    func rejectsProfileSemanticNoOp() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let noOp = makeSnapshot(generation: 2, count: 2)
        let profile = BarlineProfile(
            id: UUID(103),
            name: "Must move",
            layout: ProfileLayout(hidden: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, noOp])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(
            throws: MenuBarBackendError.operationFailed(
                "profile activation did not reach requested layout"
            )
        ) {
            try await coordinator.activate(profile: profile, now: noOp.capturedAt)
        }

        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.currentSnapshot == before)
        #expect(await backend.restoredSnapshots == [before])
    }
}

@Suite("Retry and backoff policy")
struct RetryPolicyTests {
    @Test("Backoff doubles, caps, and bounds jitter")
    func boundedExponentialBackoff() {
        let policy = RetryPolicy(
            maximumAttempts: 0,
            baseDelay: .milliseconds(100),
            maximumDelay: .milliseconds(450),
            maximumJitterPermille: 200
        )

        #expect(policy.maximumAttempts == 1)
        #expect(policy.delay(forAttempt: -1) == .milliseconds(100))
        #expect(policy.delay(forAttempt: 1) == .milliseconds(200))
        #expect(policy.delay(forAttempt: 1, jitterPermille: 200) == .milliseconds(240))
        #expect(policy.delay(forAttempt: 1, jitterPermille: 900) == .milliseconds(240))
        #expect(policy.delay(forAttempt: 3, jitterPermille: 200) == .milliseconds(450))
    }
}

private actor FakeBackend: MenuBarBackend {
    struct Activation: Equatable, Sendable {
        let itemID: MenuBarItemID
        let button: MenuBarMouseButton
    }

    let capabilities: MenuBarCapabilities

    private var snapshots: [MenuBarSnapshot]
    private(set) var restoredSnapshots = [MenuBarSnapshot]()
    private(set) var revealedItems = [MenuBarItemID]()
    private(set) var moveOperations = [MenuBarMoveOperation]()
    private(set) var activations = [Activation]()
    private(set) var maximumConcurrentMutations = 0
    private(set) var snapshotCallCount = 0
    private(set) var restartCount = 0
    private var concurrentMutations = 0
    private let mutationDelay: Duration
    private let revealFailure: MenuBarBackendError?
    private let failMoveAt: Int?
    private var snapshotFailuresRemaining: Int

    init(
        snapshots: [MenuBarSnapshot],
        capabilities: MenuBarCapabilities = MenuBarCapabilities(
            canSnapshot: true,
            canMove: true,
            canReveal: true,
            canActivate: true,
            canRestore: true
        ),
        mutationDelay: Duration = .zero,
        revealFailure: MenuBarBackendError? = nil,
        failMoveAt: Int? = nil,
        snapshotFailures: Int = 0
    ) {
        self.snapshots = snapshots
        self.capabilities = capabilities
        self.mutationDelay = mutationDelay
        self.revealFailure = revealFailure
        self.failMoveAt = failMoveAt
        snapshotFailuresRemaining = max(0, snapshotFailures)
    }

    func snapshot() throws -> MenuBarSnapshot {
        snapshotCallCount += 1
        if snapshotFailuresRemaining > 0 {
            snapshotFailuresRemaining -= 1
            throw MenuBarBackendError.interrupted
        }
        guard !snapshots.isEmpty else {
            throw MenuBarBackendError.operationFailed("no fake snapshot")
        }
        return snapshots.removeFirst()
    }

    func move(_ operation: MenuBarMoveOperation) throws -> MenuBarMutationResult {
        moveOperations.append(operation)
        if moveOperations.count == failMoveAt {
            throw MenuBarBackendError.operationFailed("injected move failure")
        }
        return MenuBarMutationResult(generation: 0, changedItemIDs: [operation.itemID])
    }

    func reveal(_ item: MenuBarItemID) async throws -> MenuBarMutationResult {
        concurrentMutations += 1
        maximumConcurrentMutations = max(maximumConcurrentMutations, concurrentMutations)
        defer { concurrentMutations -= 1 }
        try await Task.sleep(for: mutationDelay)
        if let revealFailure {
            throw revealFailure
        }
        revealedItems.append(item)
        return MenuBarMutationResult(generation: 0, changedItemIDs: [item])
    }

    func activate(_ item: MenuBarItemID, button: MenuBarMouseButton) {
        activations.append(Activation(itemID: item, button: button))
    }

    func restore(_ snapshot: MenuBarSnapshot) -> MenuBarMutationResult {
        restoredSnapshots.append(snapshot)
        return MenuBarMutationResult(
            generation: snapshot.generation,
            changedItemIDs: snapshot.items.map(\.id)
        )
    }

    func health() -> MenuBarBackendHealth {
        MenuBarBackendHealth(backendName: "Fake", state: .healthy)
    }

    func restart() {
        restartCount += 1
    }
}

private func makeSnapshot(
    generation: UInt64,
    count: Int,
    menuTracking: Bool = false
) -> MenuBarSnapshot {
    let display = MenuBarDisplayID("test-display")
    return MenuBarSnapshot(
        generation: generation,
        capturedAt: Date(),
        items: (0 ..< count).map { index in
            MenuBarItemDescriptor(
                id: MenuBarItemID(
                    bundleIdentifier: "com.example.item\(index)",
                    accessibilityIdentifier: "item-\(index)"
                ),
                section: .visible,
                order: index,
                displayID: display
            )
        },
        displayIDs: [display],
        activeSpaceIsValid: true,
        menuTrackingIsActive: menuTracking
    )
}

private func makeProfileSnapshot(
    generation: UInt64,
    layout: ProfileLayout
) -> MenuBarSnapshot {
    let display = MenuBarDisplayID("test-display")
    let items = [
        (MenuBarSection.visible, layout.visible),
        (.hidden, layout.hidden),
        (.alwaysHidden, layout.alwaysHidden),
    ].flatMap { section, itemIDs in
        itemIDs.enumerated().map { index, itemID in
            MenuBarItemDescriptor(
                id: itemID,
                section: section,
                order: index,
                displayID: display
            )
        }
    }
    return MenuBarSnapshot(
        generation: generation,
        capturedAt: Date(),
        items: items,
        displayIDs: [display],
        activeSpaceIsValid: true
    )
}

private extension UUID {
    init(_ suffix: UInt8) {
        self.init(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
    }
}
