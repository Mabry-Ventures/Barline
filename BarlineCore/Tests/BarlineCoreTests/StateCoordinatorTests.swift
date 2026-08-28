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

    @Test("Authority refresh binds the old generation and returns fresh state")
    func refreshesBoundAuthority() async throws {
        let original = makeSnapshot(generation: 1, count: 3)
        let refreshed = makeSnapshot(generation: 2, count: 3)
        let backend = FakeBackend(snapshots: [original, refreshed])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: original.capturedAt)

        await #expect(
            throws: MenuBarAuthorityRefreshError.staleGeneration(
                expected: 0,
                actual: original.generation
            )
        ) {
            try await coordinator.refreshAuthority(
                expectedGeneration: 0,
                now: refreshed.capturedAt
            )
        }
        #expect(await backend.snapshotCallCount == 1)

        let result = try await coordinator.refreshAuthority(
            expectedGeneration: original.generation,
            now: refreshed.capturedAt
        )

        #expect(result == refreshed)
        #expect(await coordinator.currentSnapshot == refreshed)
        #expect(await backend.snapshotCallCount == 2)
    }

    @Test("Stale authority cannot refresh or execute after state advances")
    func rejectsStaleExecutionAuthority() async throws {
        let original = makeSnapshot(generation: 1, count: 3)
        let refreshed = makeSnapshot(generation: 2, count: 3)
        let advanced = makeSnapshot(generation: 3, count: 3)
        let backend = FakeBackend(snapshots: [original, refreshed, advanced])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: original.capturedAt)
        _ = try await coordinator.refreshAuthority(
            expectedGeneration: original.generation,
            now: refreshed.capturedAt
        )
        _ = try await coordinator.refresh(now: advanced.capturedAt)

        await #expect(
            throws: MenuBarAuthorityRefreshError.staleGeneration(
                expected: refreshed.generation,
                actual: advanced.generation
            )
        ) {
            try await coordinator.perform(
                .reveal(original.items[0].id),
                expectedGeneration: refreshed.generation,
                now: advanced.capturedAt
            )
        }
        #expect(await backend.revealedItems.isEmpty)
    }

    @Test("Failed post-mutation validation restores the prior snapshot")
    func rollsBackInvalidMutation() async throws {
        let before = makeSnapshot(generation: 1, count: 4)
        let invalidAfter = makeSnapshot(generation: 2, count: 0)
        let verifiedRollback = makeSnapshot(generation: 3, count: 4)
        let backend = FakeBackend(snapshots: [before, invalidAfter, verifiedRollback])
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

        #expect(await coordinator.currentSnapshot == verifiedRollback)
        #expect(await backend.restoredSnapshots == [before])
    }

    @Test("Reveal rolls back when the target remains hidden")
    func rejectsRevealNoOp() async throws {
        let itemID = MenuBarItemID(
            bundleIdentifier: "com.example.hidden",
            accessibilityIdentifier: "hidden"
        )
        let layout = ProfileLayout(hidden: [itemID])
        let before = makeProfileSnapshot(generation: 1, layout: layout)
        let hiddenAfter = makeProfileSnapshot(generation: 2, layout: layout)
        let verifiedRollback = makeProfileSnapshot(generation: 3, layout: layout)
        let backend = FakeBackend(snapshots: [before, hiddenAfter, verifiedRollback])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.self) {
            try await coordinator.perform(.reveal(itemID), now: hiddenAfter.capturedAt)
        }

        #expect(await coordinator.currentSnapshot == verifiedRollback)
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

    @Test("Rollback rejects a logically similar layout on the wrong display")
    func rejectsWrongDisplayRollback() async throws {
        let before = makeSnapshot(generation: 1, count: 3)
        let invalidAfter = makeSnapshot(generation: 2, count: 0)
        let wrongDisplayRollback = makeSnapshot(
            generation: 3,
            count: 3,
            display: MenuBarDisplayID("other-display")
        )
        let backend = FakeBackend(snapshots: [before, invalidAfter, wrongDisplayRollback])
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

        #expect(await coordinator.currentSnapshot == nil)
        #expect(await coordinator.lastKnownGoodSnapshot == before)
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

    @Test("Public refresh waits for an active mutation before publishing")
    func serializesRefreshWithMutation() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let afterMutation = makeSnapshot(generation: 2, count: 2)
        let afterRefresh = makeSnapshot(generation: 3, count: 2)
        let backend = FakeBackend(
            snapshots: [before, afterMutation, afterRefresh],
            mutationDelay: .milliseconds(25)
        )
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        let mutation = Task {
            try await coordinator.perform(.reveal(before.items[0].id), now: afterMutation.capturedAt)
        }
        await backend.waitUntilMutationStarted()
        let refresh = Task {
            try await coordinator.refresh(now: afterRefresh.capturedAt)
        }

        #expect(try await mutation.value == afterMutation)
        #expect(try await refresh.value == afterRefresh)
        #expect(await coordinator.currentSnapshot == afterRefresh)
        #expect(await coordinator.lastKnownGoodSnapshot == afterRefresh)
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
        let verifiedRollback = makeSnapshot(generation: 2, count: 2)
        let backend = FakeBackend(
            snapshots: [before, verifiedRollback],
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
        #expect(await coordinator.currentSnapshot == verifiedRollback)
        #expect(await coordinator.lastKnownGoodSnapshot == verifiedRollback)
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

    @Test("Replacement helper generations are rebased monotonically")
    func rebasesReplacementHelperGeneration() async throws {
        let before = makeSnapshot(generation: 50, count: 2)
        let replacementFirst = makeSnapshot(generation: 1, count: 2)
        let replacementSecond = makeSnapshot(generation: 2, count: 2)
        let backend = FakeBackend(snapshots: [before, replacementFirst, replacementSecond])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        let recovered = try await coordinator.recover(now: replacementFirst.capturedAt)
        let refreshed = try await coordinator.refresh(now: replacementSecond.capturedAt)

        #expect(recovered.generation == 51)
        #expect(refreshed.generation == 52)
    }

    @Test("Invalid replacement helper keeps prior authority")
    func invalidReplacementKeepsPriorAuthority() async throws {
        let before = makeSnapshot(generation: 50, count: 2)
        let wrong = makeProfileSnapshot(
            generation: 1,
            layout: ProfileLayout(hidden: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, wrong])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.self) {
            try await coordinator.recover(now: wrong.capturedAt)
        }

        #expect(await coordinator.currentSnapshot == nil)
        #expect(await coordinator.lastKnownGoodSnapshot == before)
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

    @Test("Workspace settings commit and restore inside layout history")
    func restoresWorkspaceWithHistory() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let freshBefore = makeSnapshot(generation: 2, count: 2)
        let after = makeSnapshot(generation: 3, count: 2)
        let liveAfter = makeSnapshot(generation: 4, count: 2)
        let restoredBefore = makeSnapshot(generation: 5, count: 2)
        let profile = BarlineProfile(
            id: UUID(120),
            name: "Workspace",
            layout: ProfileLayout(visible: before.items.map(\.id)),
            appearance: ProfileAppearance(itemSpacing: 6),
            shelfBehavior: ProfileShelfBehavior(isEnabled: true)
        )
        let original = ProfileWorkspaceState(
            appearance: ProfileAppearance(itemSpacing: -3),
            shelfBehavior: ProfileShelfBehavior(isEnabled: false),
            revealTriggers: ProfileRevealTriggers(),
            autoRehide: ProfileAutoRehide(),
            applicationMenuOverlapBehavior: .leaveVisible
        )
        let recorder = WorkspaceRecorder(initial: original)
        let transaction = MenuBarWorkspaceTransaction(
            capture: { await recorder.capture() },
            apply: { try await recorder.apply($0) }
        )
        let backend = FakeBackend(snapshots: [before, freshBefore, after, liveAfter, restoredBefore])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        _ = try await coordinator.activate(
            profile: profile,
            now: after.capturedAt,
            workspaceTransaction: transaction
        )
        _ = try await coordinator.undo(
            now: restoredBefore.capturedAt,
            workspaceTransaction: transaction
        )

        #expect(await recorder.values == [ProfileWorkspaceState(profile: profile), original])
        #expect(await coordinator.activeProfileID == nil)
    }

    @Test("Profile activation verifies the selected display before committing authority")
    func rejectsProfileResultOnWrongDisplay() async throws {
        let firstDisplay = MenuBarDisplayID("first-display")
        let secondDisplay = MenuBarDisplayID("second-display")
        let firstItem = MenuBarItemID(
            bundleIdentifier: "com.example.first",
            accessibilityIdentifier: "first"
        )
        let secondItem = MenuBarItemID(
            bundleIdentifier: "com.example.second",
            accessibilityIdentifier: "second"
        )
        func snapshot(_ generation: UInt64, swapped: Bool) -> MenuBarSnapshot {
            MenuBarSnapshot(
                generation: generation,
                capturedAt: Date(),
                items: [
                    MenuBarItemDescriptor(
                        id: firstItem,
                        section: .visible,
                        order: 0,
                        displayID: swapped ? secondDisplay : firstDisplay,
                        isOnScreen: true
                    ),
                    MenuBarItemDescriptor(
                        id: secondItem,
                        section: .visible,
                        order: 1,
                        displayID: swapped ? firstDisplay : secondDisplay,
                        isOnScreen: true
                    ),
                ],
                displayIDs: [firstDisplay, secondDisplay],
                activeSpaceIsValid: true
            )
        }
        let before = snapshot(1, swapped: false)
        let wrongDisplayResult = snapshot(2, swapped: true)
        let verifiedRollback = snapshot(3, swapped: false)
        let profile = BarlineProfile(
            id: UUID(124),
            name: "First display",
            layout: ProfileLayout(visible: [firstItem])
        )
        let backend = FakeBackend(snapshots: [before, wrongDisplayResult, verifiedRollback])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.self) {
            try await coordinator.activate(
                profile: profile,
                on: firstDisplay,
                now: wrongDisplayResult.capturedAt
            )
        }

        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.currentSnapshot == verifiedRollback)
        #expect(await backend.restoredSnapshots == [before])
    }

    @Test("A partially applied workspace failure restores and verifies both workspace and layout")
    func rollsBackPartialWorkspaceFailure() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let freshBefore = makeSnapshot(generation: 2, count: 2)
        let verifiedRollback = makeSnapshot(generation: 3, count: 2)
        let original = ProfileWorkspaceState(profile: BarlineProfile(name: "Original"))
        let targetProfile = BarlineProfile(
            id: UUID(125),
            name: "Target",
            layout: ProfileLayout(visible: before.items.map(\.id)),
            appearance: ProfileAppearance(itemSpacing: 4)
        )
        let recorder = WorkspaceRecorder(initial: original, partialFailApplyNumbers: [1])
        let transaction = MenuBarWorkspaceTransaction(
            capture: { await recorder.capture() },
            apply: { try await recorder.apply($0) }
        )
        let backend = FakeBackend(snapshots: [before, freshBefore, verifiedRollback])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.self) {
            try await coordinator.activate(
                profile: targetProfile,
                now: freshBefore.capturedAt,
                workspaceTransaction: transaction
            )
        }

        #expect(await recorder.capture() == original)
        #expect(await recorder.values == [ProfileWorkspaceState(profile: targetProfile), original])
        #expect(await backend.restoredSnapshots == [freshBefore])
        #expect(await coordinator.currentSnapshot == verifiedRollback)
        #expect(await coordinator.activeProfileID == nil)
    }

    @Test("Unverified activation rollback clears current authority")
    func clearsAuthorityWhenActivationRollbackFails() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let freshBefore = makeSnapshot(generation: 2, count: 2)
        let profile = BarlineProfile(
            id: UUID(121),
            name: "Rollback",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let original = ProfileWorkspaceState(profile: BarlineProfile(name: "Original"))
        let recorder = WorkspaceRecorder(initial: original, failApplyNumbers: [2])
        let transaction = MenuBarWorkspaceTransaction(
            capture: { await recorder.capture() },
            apply: { try await recorder.apply($0) }
        )
        let backend = FakeBackend(
            snapshots: [before, freshBefore],
            failMoveAt: 1,
            restoreFailures: 1
        )
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        await #expect(throws: MenuBarBackendError.self) {
            try await coordinator.activate(
                profile: profile,
                now: before.capturedAt,
                workspaceTransaction: transaction
            )
        }

        #expect(await coordinator.currentSnapshot == nil)
        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.lastKnownGoodSnapshot == freshBefore)
    }

    @Test("Stored workspace checkpoints validate before side effects")
    func rejectsInvalidStoredWorkspaceCheckpoint() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let invalidWorkspace = ProfileWorkspaceState(
            appearance: ProfileAppearance(itemSpacing: .nan),
            shelfBehavior: ProfileShelfBehavior(),
            revealTriggers: ProfileRevealTriggers(),
            autoRehide: ProfileAutoRehide(),
            applicationMenuOverlapBehavior: .hideWhenNeeded
        )
        let checkpoint = MenuBarWorkspaceCheckpoint(
            snapshot: before,
            activeProfileID: nil,
            workspace: invalidWorkspace
        )
        let recorder = WorkspaceRecorder(
            initial: ProfileWorkspaceState(profile: BarlineProfile(name: "Current"))
        )
        let transaction = MenuBarWorkspaceTransaction(
            capture: { await recorder.capture() },
            apply: { try await recorder.apply($0) }
        )
        let backend = FakeBackend(snapshots: [])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )

        await #expect(throws: ProfileValidationError.invalidAppearance) {
            try await coordinator.restoreWorkspaceCheckpoint(
                checkpoint,
                workspaceTransaction: transaction
            )
        }
        #expect(await backend.restoredSnapshots.isEmpty)
        #expect(await recorder.values.isEmpty)
    }

    @Test("Redo captures a live externally changed inverse layout")
    func redoUsesLiveExternalInverse() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let external = makeProfileSnapshot(
            generation: 3,
            layout: ProfileLayout(hidden: before.items.map(\.id))
        )
        let restoredBefore = makeSnapshot(generation: 4, count: 2)
        let liveBefore = makeSnapshot(generation: 5, count: 2)
        let restoredExternal = makeProfileSnapshot(
            generation: 6,
            layout: ProfileLayout(hidden: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [
            before, after, external, restoredBefore, liveBefore, restoredExternal,
        ])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.perform(.reveal(before.items[0].id), now: after.capturedAt)

        _ = try await coordinator.undo(now: restoredBefore.capturedAt)
        let redone = try await coordinator.redo(now: restoredExternal.capturedAt)

        #expect(await backend.restoredSnapshots == [before, external])
        #expect(redone == restoredExternal)
    }

    @Test("Profile activation resolves the active display override through the helper boundary")
    func activatesActiveDisplayOverride() async throws {
        let before = makeSnapshot(generation: 1, count: 3)
        let activeDisplay = MenuBarDisplayID("test-display")
        let overrideLayout = ProfileLayout(
            visible: [before.items[1].id],
            hidden: [before.items[2].id],
            alwaysHidden: [before.items[0].id]
        )
        let profile = BarlineProfile(
            id: UUID(101),
            name: "Presentation",
            layout: ProfileLayout(visible: before.items.map(\.id)),
            displayOverrides: [
                DisplayProfileOverride(displayID: activeDisplay, layout: overrideLayout),
            ]
        )
        let after = makeProfileSnapshot(generation: 2, layout: overrideLayout)
        let backend = FakeBackend(
            snapshots: [before, after],
            environment: MenuBarEnvironmentSnapshot(
                activeDisplayID: 7,
                activeStableDisplayID: activeDisplay,
                activeSpaceToken: 42,
                activeSpaceIsFullscreen: false
            )
        )
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        _ = try await coordinator.activate(profile: profile, now: after.capturedAt)

        #expect(await backend.moveOperations.map(\.itemID) == overrideLayout.allItemIDs)
        #expect(await backend.moveOperations.allSatisfy {
            $0.destinationDisplayID == activeDisplay
        })
        #expect(await coordinator.activeProfileID == profile.id)
    }

    @Test("A partially applied profile is rolled back and never becomes authoritative")
    func rollsBackPartialProfileActivation() async throws {
        let before = makeSnapshot(generation: 1, count: 3)
        let profile = BarlineProfile(
            id: UUID(101),
            name: "Broken",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let verifiedRollback = makeSnapshot(generation: 2, count: 3)
        let backend = FakeBackend(snapshots: [before, verifiedRollback], failMoveAt: 2)
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
        #expect(await coordinator.currentSnapshot == verifiedRollback)
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
        let second = makeProfileSnapshot(
            generation: 2,
            layout: ProfileLayout(
                visible: [first.items[1].id],
                hidden: [first.items[0].id]
            )
        )
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

    @Test("Move postcondition rejects the wrong section-relative ordinal")
    func rejectsWrongMoveOrdinal() async throws {
        let before = makeSnapshot(generation: 1, count: 3)
        let wrong = makeProfileSnapshot(
            generation: 2,
            layout: ProfileLayout(
                visible: [before.items[2].id],
                hidden: [before.items[1].id, before.items[0].id]
            )
        )
        let verifiedRollback = makeSnapshot(generation: 3, count: 3)
        let operation = MenuBarMoveOperation(
            itemID: before.items[0].id,
            section: .hidden,
            index: 0
        )
        let backend = FakeBackend(snapshots: [before, wrong, verifiedRollback])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )

        await #expect(throws: MenuBarBackendError.operationFailed(
            "menu bar move did not reach requested section"
        )) {
            try await coordinator.perform(.move(operation), now: wrong.capturedAt)
        }
        #expect(await backend.restoredSnapshots == [before])
        #expect(await coordinator.currentSnapshot == verifiedRollback)
    }

    @Test("Layout mutations create bounded undo and redo checkpoints")
    func undoesAndRedoesLayoutMutation() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let liveAfter = makeSnapshot(generation: 3, count: 2)
        let restoredBefore = makeSnapshot(generation: 4, count: 2)
        let liveBefore = makeSnapshot(generation: 5, count: 2)
        let restoredAfter = makeSnapshot(generation: 6, count: 2)
        let backend = FakeBackend(snapshots: [
            before, after, liveAfter, restoredBefore, liveBefore, restoredAfter,
        ])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.perform(.reveal(before.items[0].id), now: after.capturedAt)

        #expect(await coordinator.canUndo)
        _ = try await coordinator.undo(now: restoredBefore.capturedAt)
        #expect(await coordinator.canRedo)
        _ = try await coordinator.redo(now: restoredAfter.capturedAt)

        #expect(await backend.restoredSnapshots == [before, liveAfter])
        #expect(await coordinator.currentSnapshot == restoredAfter)
        #expect(await coordinator.canUndo)
        #expect(await coordinator.canRedo == false)
    }

    @Test("Click activation does not create a layout undo checkpoint")
    func clickDoesNotCreateUndoHistory() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let afterClick = makeSnapshot(generation: 2, count: 2)
        let backend = FakeBackend(snapshots: [before, afterClick])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        _ = try await coordinator.perform(
            .activate(before.items[0].id, .left),
            now: afterClick.capturedAt
        )

        #expect(await coordinator.canUndo == false)
        #expect(await coordinator.canRedo == false)
    }

    @Test("Click activation preserves an existing redo checkpoint")
    func clickPreservesRedoHistory() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let afterReveal = makeSnapshot(generation: 2, count: 2)
        let liveAfterReveal = makeSnapshot(generation: 3, count: 2)
        let restoredBefore = makeSnapshot(generation: 4, count: 2)
        let afterClick = makeSnapshot(generation: 5, count: 2)
        let liveAfterClick = makeSnapshot(generation: 6, count: 2)
        let restoredAfter = makeSnapshot(generation: 7, count: 2)
        let backend = FakeBackend(snapshots: [
            before,
            afterReveal,
            liveAfterReveal,
            restoredBefore,
            afterClick,
            liveAfterClick,
            restoredAfter,
        ])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.perform(.reveal(before.items[0].id), now: afterReveal.capturedAt)
        _ = try await coordinator.undo(now: restoredBefore.capturedAt)

        _ = try await coordinator.perform(
            .activate(before.items[1].id, .right),
            now: afterClick.capturedAt
        )

        #expect(await coordinator.canRedo)
        _ = try await coordinator.redo(now: restoredAfter.capturedAt)
        #expect(await coordinator.currentSnapshot == restoredAfter)
        #expect(await coordinator.canRedo == false)
    }

    @Test("Structurally valid wrong history layout rolls back")
    func rollsBackWrongHistoryLayout() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let liveAfter = makeSnapshot(generation: 3, count: 2)
        let wrongLayout = ProfileLayout(hidden: before.items.map(\.id))
        let wrongButValid = makeProfileSnapshot(generation: 4, layout: wrongLayout)
        let verifiedAfter = makeSnapshot(generation: 5, count: 2)
        let backend = FakeBackend(snapshots: [
            before, after, liveAfter, wrongButValid, verifiedAfter,
        ])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.perform(.reveal(before.items[0].id), now: after.capturedAt)

        await #expect(
            throws: MenuBarBackendError.operationFailed(
                "history restore did not reach requested layout"
            )
        ) {
            try await coordinator.undo(now: wrongButValid.capturedAt)
        }

        #expect(await backend.restoredSnapshots == [before, liveAfter])
        #expect(await coordinator.currentSnapshot == verifiedAfter)
        #expect(await coordinator.lastKnownGoodSnapshot == verifiedAfter)
        #expect(await coordinator.canUndo)
        #expect(await coordinator.canRedo == false)
    }

    @Test("Profile identity follows layout history through undo and redo")
    func restoresProfileIdentityWithHistory() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let afterFirst = makeSnapshot(generation: 2, count: 2)
        let afterSecond = makeSnapshot(generation: 3, count: 2)
        let liveSecond = makeSnapshot(generation: 4, count: 2)
        let restoredFirst = makeSnapshot(generation: 5, count: 2)
        let liveFirst = makeSnapshot(generation: 6, count: 2)
        let restoredSecond = makeSnapshot(generation: 7, count: 2)
        let firstProfile = BarlineProfile(
            id: UUID(104),
            name: "First",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let secondProfile = BarlineProfile(
            id: UUID(105),
            name: "Second",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [
            before,
            afterFirst,
            afterSecond,
            liveSecond,
            restoredFirst,
            liveFirst,
            restoredSecond,
        ])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.activate(profile: firstProfile, now: afterFirst.capturedAt)
        _ = try await coordinator.activate(profile: secondProfile, now: afterSecond.capturedAt)

        _ = try await coordinator.undo(now: restoredFirst.capturedAt)
        #expect(await coordinator.activeProfileID == firstProfile.id)

        _ = try await coordinator.redo(now: restoredSecond.capturedAt)
        #expect(await coordinator.activeProfileID == secondProfile.id)
        #expect(await backend.restoredSnapshots == [afterFirst, liveSecond])
    }

    @Test("Failed history restore rolls back snapshot and profile identity")
    func rollsBackFailedHistoryRestore() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let liveAfter = makeSnapshot(generation: 3, count: 2)
        let verifiedAfter = makeSnapshot(generation: 4, count: 2)
        let profile = BarlineProfile(
            id: UUID(106),
            name: "Current",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(
            snapshots: [before, after, liveAfter, verifiedAfter],
            restoreFailures: 1
        )
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.activate(profile: profile, now: after.capturedAt)

        await #expect(throws: MenuBarBackendError.interrupted) {
            try await coordinator.undo(now: after.capturedAt)
        }

        #expect(await backend.restoredSnapshots == [before, liveAfter])
        #expect(await coordinator.currentSnapshot == verifiedAfter)
        #expect(await coordinator.lastKnownGoodSnapshot == verifiedAfter)
        #expect(await coordinator.activeProfileID == profile.id)
        #expect(await coordinator.canUndo)
        #expect(await coordinator.canRedo == false)
    }

    @Test("Invalid post-history snapshot rolls back snapshot and profile identity")
    func rollsBackInvalidHistorySnapshot() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let liveAfter = makeSnapshot(generation: 3, count: 2)
        let invalid = makeSnapshot(generation: 4, count: 0)
        let verifiedAfter = makeSnapshot(generation: 5, count: 2)
        let profile = BarlineProfile(
            id: UUID(107),
            name: "Current",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, after, liveAfter, invalid, verifiedAfter])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.activate(profile: profile, now: after.capturedAt)

        await #expect(throws: MenuBarBackendError.invalidSnapshot(.emptySnapshot)) {
            try await coordinator.undo(now: invalid.capturedAt)
        }

        #expect(await backend.restoredSnapshots == [before, liveAfter])
        #expect(await coordinator.currentSnapshot == verifiedAfter)
        #expect(await coordinator.lastKnownGoodSnapshot == verifiedAfter)
        #expect(await coordinator.activeProfileID == profile.id)
        #expect(await coordinator.lastRejection == .emptySnapshot)
        #expect(await coordinator.canUndo)
        #expect(await coordinator.canRedo == false)
    }

    @Test("Profile authority can be conservatively cleared without mutating the layout")
    func clearsProfileAuthority() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let profile = BarlineProfile(
            id: UUID(109),
            name: "Current",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, after])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.activate(profile: profile, now: after.capturedAt)

        await coordinator.clearActiveProfileAuthority()

        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.currentSnapshot == after)
        #expect(await backend.restoredSnapshots.isEmpty)
    }

    @Test("Manual layout mutations revoke active profile authority")
    func layoutMutationClearsProfileAuthority() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let activated = makeSnapshot(generation: 2, count: 2)
        let revealed = makeSnapshot(generation: 3, count: 2)
        let profile = BarlineProfile(
            id: UUID(110),
            name: "Current",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, activated, revealed])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.activate(profile: profile, now: activated.capturedAt)

        _ = try await coordinator.perform(.reveal(before.items[0].id), now: revealed.capturedAt)

        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.canUndo)
    }

    @Test("Failed history rollback clears unverified current authority")
    func clearsAuthorityWhenHistoryRollbackFails() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let liveAfter = makeSnapshot(generation: 3, count: 2)
        let invalid = makeSnapshot(generation: 4, count: 0)
        let profile = BarlineProfile(
            id: UUID(108),
            name: "Current",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(
            snapshots: [before, after, liveAfter, invalid],
            restoreFailureCallNumbers: [2]
        )
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.activate(profile: profile, now: after.capturedAt)

        do {
            _ = try await coordinator.undo(now: invalid.capturedAt)
            Issue.record("Expected history rollback failure")
        } catch let MenuBarBackendError.operationFailed(message) {
            #expect(message.contains("history restore failed"))
            #expect(message.contains("rollback failed"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await backend.restoredSnapshots == [before, liveAfter])
        #expect(await coordinator.currentSnapshot == nil)
        #expect(await coordinator.lastKnownGoodSnapshot == liveAfter)
        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.canUndo)
        #expect(await coordinator.canRedo == false)
    }

    @Test("Semantically unverifiable history rollback clears current authority")
    func clearsAuthorityWhenHistoryRollbackLayoutDoesNotMatch() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let after = makeSnapshot(generation: 2, count: 2)
        let liveAfter = makeSnapshot(generation: 3, count: 2)
        let invalid = makeSnapshot(generation: 4, count: 0)
        let wrongRollback = makeProfileSnapshot(
            generation: 5,
            layout: ProfileLayout(hidden: before.items.map(\.id))
        )
        let profile = BarlineProfile(
            id: UUID(109),
            name: "Current",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, after, liveAfter, invalid, wrongRollback])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)
        _ = try await coordinator.activate(profile: profile, now: after.capturedAt)

        do {
            _ = try await coordinator.undo(now: invalid.capturedAt)
            Issue.record("Expected history rollback verification failure")
        } catch let MenuBarBackendError.operationFailed(message) {
            #expect(message.contains("history restore failed"))
            #expect(message.contains("rollback failed"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await backend.restoredSnapshots == [before, liveAfter])
        #expect(await coordinator.currentSnapshot == nil)
        #expect(await coordinator.lastKnownGoodSnapshot == liveAfter)
        #expect(await coordinator.activeProfileID == nil)
        #expect(await coordinator.canUndo)
        #expect(await coordinator.canRedo == false)
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

    @Test("Last-known-good restore rejects a structurally valid wrong layout")
    func rejectsWrongLastKnownGoodLayout() async throws {
        let itemIDs = [
            MenuBarItemID(bundleIdentifier: "com.example.first", accessibilityIdentifier: "first"),
            MenuBarItemID(bundleIdentifier: "com.example.second", accessibilityIdentifier: "second"),
        ]
        let before = makeProfileSnapshot(
            generation: 1,
            layout: ProfileLayout(visible: itemIDs)
        )
        let wrong = makeProfileSnapshot(
            generation: 2,
            layout: ProfileLayout(visible: Array(itemIDs.reversed()))
        )
        let verifiedRollback = makeProfileSnapshot(
            generation: 3,
            layout: ProfileLayout(visible: itemIDs)
        )
        let backend = FakeBackend(snapshots: [before, wrong, verifiedRollback])
        let coordinator = MenuBarStateCoordinator(
            backend: backend,
            retryPolicy: RetryPolicy(maximumAttempts: 1, baseDelay: .zero, maximumDelay: .zero)
        )
        _ = try await coordinator.refresh(now: before.capturedAt)

        do {
            _ = try await coordinator.perform(.restoreLastKnownGood, now: wrong.capturedAt)
            Issue.record("Expected last-known-good layout verification failure")
        } catch let MenuBarBackendError.operationFailed(message) {
            #expect(message.contains("did not reach requested layout"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await backend.restoredSnapshots == [before, before])
        #expect(await coordinator.currentSnapshot == verifiedRollback)
        #expect(await coordinator.lastKnownGoodSnapshot == verifiedRollback)
    }

    @Test("Invalid profile post-snapshot rolls back and records the rejection")
    func rollsBackInvalidProfileSnapshot() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let invalid = makeSnapshot(generation: 2, count: 0)
        let verifiedRollback = makeSnapshot(generation: 3, count: 2)
        let profile = BarlineProfile(
            id: UUID(102),
            name: "Invalid result",
            layout: ProfileLayout(visible: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, invalid, verifiedRollback])
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
        #expect(await coordinator.currentSnapshot == verifiedRollback)
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
        #expect(await coordinator.currentSnapshot == nil)
    }

    @Test("A structurally valid no-op snapshot cannot commit a profile")
    func rejectsProfileSemanticNoOp() async throws {
        let before = makeSnapshot(generation: 1, count: 2)
        let noOp = makeSnapshot(generation: 2, count: 2)
        let verifiedRollback = makeSnapshot(generation: 3, count: 2)
        let profile = BarlineProfile(
            id: UUID(103),
            name: "Must move",
            layout: ProfileLayout(hidden: before.items.map(\.id))
        )
        let backend = FakeBackend(snapshots: [before, noOp, verifiedRollback])
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
        #expect(await coordinator.currentSnapshot == verifiedRollback)
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

private actor WorkspaceRecorder {
    private var current: ProfileWorkspaceState
    private(set) var values = [ProfileWorkspaceState]()
    private let failApplyNumbers: Set<Int>
    private let partialFailApplyNumbers: Set<Int>
    private var applyCount = 0

    init(
        initial: ProfileWorkspaceState,
        failApplyNumbers: Set<Int> = [],
        partialFailApplyNumbers: Set<Int> = []
    ) {
        current = initial
        self.failApplyNumbers = failApplyNumbers
        self.partialFailApplyNumbers = partialFailApplyNumbers
    }

    func capture() -> ProfileWorkspaceState {
        current
    }

    func apply(_ value: ProfileWorkspaceState) throws {
        applyCount += 1
        if failApplyNumbers.contains(applyCount) {
            throw MenuBarBackendError.operationFailed("injected workspace failure")
        }
        current = value
        values.append(value)
        if partialFailApplyNumbers.contains(applyCount) {
            throw MenuBarBackendError.operationFailed("injected partial workspace failure")
        }
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
    private var mutationStarted = false
    private var mutationStartWaiters = [CheckedContinuation<Void, Never>]()
    private let mutationDelay: Duration
    private let revealFailure: MenuBarBackendError?
    private let failMoveAt: Int?
    private let environmentSnapshot: MenuBarEnvironmentSnapshot?
    private var snapshotFailuresRemaining: Int
    private var restoreFailuresRemaining: Int
    private let restoreFailureCallNumbers: Set<Int>
    private var restoreCallCount = 0

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
        environment: MenuBarEnvironmentSnapshot? = nil,
        snapshotFailures: Int = 0,
        restoreFailures: Int = 0,
        restoreFailureCallNumbers: Set<Int> = []
    ) {
        self.snapshots = snapshots
        self.capabilities = capabilities
        self.mutationDelay = mutationDelay
        self.revealFailure = revealFailure
        self.failMoveAt = failMoveAt
        environmentSnapshot = environment
        snapshotFailuresRemaining = max(0, snapshotFailures)
        restoreFailuresRemaining = max(0, restoreFailures)
        self.restoreFailureCallNumbers = restoreFailureCallNumbers
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
        mutationStarted = true
        let waiters = mutationStartWaiters
        mutationStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        defer { concurrentMutations -= 1 }
        try await Task.sleep(for: mutationDelay)
        if let revealFailure {
            throw revealFailure
        }
        revealedItems.append(item)
        return MenuBarMutationResult(generation: 0, changedItemIDs: [item])
    }

    func waitUntilMutationStarted() async {
        guard !mutationStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            mutationStartWaiters.append(continuation)
        }
    }

    func activate(_ item: MenuBarItemID, button: MenuBarMouseButton) {
        activations.append(Activation(itemID: item, button: button))
    }

    func environment() throws -> MenuBarEnvironmentSnapshot {
        guard let environmentSnapshot else {
            throw MenuBarBackendError.unavailableCapability("environment")
        }
        return environmentSnapshot
    }

    func restore(_ snapshot: MenuBarSnapshot) throws -> MenuBarMutationResult {
        restoreCallCount += 1
        restoredSnapshots.append(snapshot)
        if restoreFailureCallNumbers.contains(restoreCallCount) || restoreFailuresRemaining > 0 {
            restoreFailuresRemaining -= 1
            throw MenuBarBackendError.interrupted
        }
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
    menuTracking: Bool = false,
    display: MenuBarDisplayID = MenuBarDisplayID("test-display")
) -> MenuBarSnapshot {
    MenuBarSnapshot(
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
                displayID: display,
                isOnScreen: true
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
                displayID: display,
                isOnScreen: section == .visible
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
