//
//  StateCoordinator.swift
//  Barline
//

import Foundation

public enum MenuBarAuthorityRefreshError: Error, Equatable, Sendable {
    case staleGeneration(expected: UInt64, actual: UInt64?)
}

public enum MenuBarMutation: Sendable {
    case move(MenuBarMoveOperation)
    case reveal(MenuBarItemID)
    case activate(MenuBarItemID, MenuBarMouseButton)
    case restoreLastKnownGood

    fileprivate var recordsLayoutHistory: Bool {
        if case .activate = self {
            false
        } else {
            true
        }
    }
}

public struct RetryPolicy: Sendable {
    public let maximumAttempts: Int
    public let baseDelay: Duration
    public let maximumDelay: Duration
    public let maximumJitterPermille: Int

    public init(
        maximumAttempts: Int = 4,
        baseDelay: Duration = .milliseconds(100),
        maximumDelay: Duration = .seconds(2),
        maximumJitterPermille: Int = 200
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.maximumJitterPermille = min(max(maximumJitterPermille, 0), 1000)
    }

    public func delay(forAttempt attempt: Int) -> Duration {
        delay(forAttempt: attempt, jitterPermille: 0)
    }

    public func delay(forAttempt attempt: Int, jitterPermille: Int) -> Duration {
        let shift = min(max(attempt, 0), 20)
        let multiplier = 1 << shift
        let exponential = min(baseDelay * multiplier, maximumDelay)
        let boundedJitter = min(max(jitterPermille, 0), maximumJitterPermille)
        return min(exponential + (exponential * boundedJitter / 1000), maximumDelay)
    }
}

public actor MenuBarStateCoordinator {
    private struct HistoryCheckpoint: Sendable {
        let snapshot: MenuBarSnapshot
        let activeProfileID: UUID?
    }

    private struct LogicalLayoutItem: Hashable, Sendable {
        let id: MenuBarItemID
        let section: MenuBarSection
        let order: Int
    }

    public private(set) var currentSnapshot: MenuBarSnapshot?
    public private(set) var lastKnownGoodSnapshot: MenuBarSnapshot?
    public private(set) var lastRejection: SnapshotRejectionReason?
    public private(set) var mutationGeneration: UInt64 = 0
    public private(set) var activeProfileID: UUID?
    public private(set) var backendHealth = MenuBarBackendHealth(
        backendName: "Unprobed",
        state: .unavailable
    )

    private let backend: any MenuBarBackend
    private let validator: SnapshotValidator
    private let retryPolicy: RetryPolicy
    private let historyLimit = 50
    private var mutationIsActive = false
    private var mutationWaiters = [CheckedContinuation<Void, Never>]()
    private var undoCheckpoints = [HistoryCheckpoint]()
    private var redoCheckpoints = [HistoryCheckpoint]()

    public init(
        backend: any MenuBarBackend,
        validator: SnapshotValidator = SnapshotValidator(),
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.backend = backend
        self.validator = validator
        self.retryPolicy = retryPolicy
    }

    @discardableResult
    public func refresh(now: Date = Date()) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        return try await refreshAssumingMutationTurn(now: now)
    }

    /// Refreshes only while the caller's previously validated authority is
    /// still current. The check and refresh share the mutation turn, preventing
    /// a layout mutation from slipping between them.
    @discardableResult
    public func refreshAuthority(
        expectedGeneration: UInt64,
        now: Date = Date()
    ) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        try requireCurrentGeneration(expectedGeneration)
        return try await refreshAssumingMutationTurn(now: now)
    }

    private func refreshAssumingMutationTurn(now: Date) async throws -> MenuBarSnapshot {
        var mostRecentError: (any Error)?

        for attempt in 0 ..< retryPolicy.maximumAttempts {
            try Task.checkCancellation()
            do {
                let candidate = try await backend.snapshot()
                switch validator.validate(candidate, previous: currentSnapshot, now: now) {
                case let .success(snapshot):
                    currentSnapshot = snapshot
                    lastKnownGoodSnapshot = snapshot
                    lastRejection = nil
                    backendHealth = await backend.health()
                    return snapshot
                case let .failure(reason):
                    lastRejection = reason
                    let health = await backend.health()
                    backendHealth = MenuBarBackendHealth(
                        backendName: health.backendName,
                        state: .degraded,
                        message: String(describing: reason)
                    )
                    mostRecentError = MenuBarBackendError.invalidSnapshot(reason)
                }
            } catch {
                mostRecentError = error
                let health = await backend.health()
                backendHealth = MenuBarBackendHealth(
                    backendName: health.backendName,
                    state: health.state == .healthy ? .degraded : health.state,
                    message: error.localizedDescription
                )
            }

            if attempt + 1 < retryPolicy.maximumAttempts {
                let jitter = Int.random(in: 0 ... retryPolicy.maximumJitterPermille)
                try await Task.sleep(
                    for: retryPolicy.delay(forAttempt: attempt, jitterPermille: jitter)
                )
            }
        }

        throw mostRecentError ?? MenuBarBackendError.operationFailed("snapshot refresh failed")
    }

    @discardableResult
    public func perform(_ mutation: MenuBarMutation, now: Date = Date()) async throws -> MenuBarSnapshot {
        try await perform(mutation, expectedGeneration: nil, now: now)
    }

    /// Executes only if the refreshed snapshot used by the caller is still
    /// authoritative when the mutation acquires its serialized turn.
    @discardableResult
    public func perform(
        _ mutation: MenuBarMutation,
        expectedGeneration: UInt64,
        now: Date = Date()
    ) async throws -> MenuBarSnapshot {
        try await perform(mutation, expectedGeneration: expectedGeneration as UInt64?, now: now)
    }

    private func perform(
        _ mutation: MenuBarMutation,
        expectedGeneration: UInt64?,
        now: Date
    ) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        try Task.checkCancellation()
        if let expectedGeneration {
            try requireCurrentGeneration(expectedGeneration)
        }
        let before = try await validatedStartingSnapshot(now: now)
        guard !before.menuTrackingIsActive else {
            throw MenuBarBackendError.unsafeMenuTracking
        }
        try validateReferences(for: mutation, in: before)
        let restoreTarget: MenuBarSnapshot? = if case .restoreLastKnownGood = mutation {
            lastKnownGoodSnapshot
        } else {
            nil
        }

        mutationGeneration &+= 1
        let generation = mutationGeneration

        do {
            try await apply(mutation)
            try Task.checkCancellation()
            let candidate = try await backend.snapshot()
            switch validator.validate(candidate, previous: before, now: now) {
            case let .success(snapshot):
                guard generation == mutationGeneration else {
                    throw CancellationError()
                }
                if let restoreTarget {
                    try validateHistoryResult(snapshot, matches: restoreTarget)
                }
                currentSnapshot = snapshot
                lastKnownGoodSnapshot = snapshot
                lastRejection = nil
                if mutation.recordsLayoutHistory {
                    recordUndoCheckpoint(before, activeProfileID: activeProfileID)
                    activeProfileID = nil
                }
                return snapshot
            case let .failure(reason):
                lastRejection = reason
                throw MenuBarBackendError.invalidSnapshot(reason)
            }
        } catch {
            if await backend.capabilities.canRestore {
                _ = try? await backend.restore(before)
            }
            currentSnapshot = before
            lastKnownGoodSnapshot = before
            throw error
        }
    }

    private func validateProfileResult(
        _ layout: ProfileLayout,
        in snapshot: MenuBarSnapshot
    ) throws {
        for (section, itemIDs) in [
            (MenuBarSection.visible, layout.visible),
            (.hidden, layout.hidden),
            (.alwaysHidden, layout.alwaysHidden),
        ] {
            for (index, itemID) in itemIDs.enumerated() {
                guard snapshot.items.contains(where: {
                    $0.id == itemID && $0.section == section && $0.order == index
                }) else {
                    throw MenuBarBackendError.operationFailed(
                        "profile activation did not reach requested layout"
                    )
                }
            }
        }
    }

    /// Applies every item move in a profile as one serialized transaction.
    /// The profile is not made authoritative until the post-operation snapshot
    /// validates; any failure restores both the prior layout and profile ID.
    @discardableResult
    public func activate(
        profile: BarlineProfile,
        on displayID: MenuBarDisplayID? = nil,
        now: Date = Date(),
        expectedGeneration: UInt64? = nil
    ) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        try Task.checkCancellation()
        if let expectedGeneration {
            try requireCurrentGeneration(expectedGeneration)
        }
        try ProfileValidator().validate(profile)
        let before = try await validatedStartingSnapshot(now: now)
        guard !before.menuTrackingIsActive else {
            throw MenuBarBackendError.unsafeMenuTracking
        }

        let activeDisplayID: MenuBarDisplayID? = if let displayID {
            displayID
        } else if let environment = try? await backend.environment(),
                  let environmentDisplayID = environment.activeStableDisplayID,
                  before.displayIDs.contains(environmentDisplayID)
        {
            environmentDisplayID
        } else {
            nil
        }
        let layout = profile.layout(for: activeDisplayID)
        let knownItemIDs = Set(before.items.map(\.id))
        for itemID in layout.allItemIDs where !knownItemIDs.contains(itemID) {
            throw MenuBarBackendError.staleItem(itemID)
        }

        let priorProfileID = activeProfileID
        mutationGeneration &+= 1
        let generation = mutationGeneration

        do {
            for (section, itemIDs) in [
                (MenuBarSection.visible, layout.visible),
                (.hidden, layout.hidden),
                (.alwaysHidden, layout.alwaysHidden),
            ] {
                for (index, itemID) in itemIDs.enumerated() {
                    _ = try await backend.move(
                        MenuBarMoveOperation(itemID: itemID, section: section, index: index)
                    )
                }
            }

            try Task.checkCancellation()
            let candidate = try await backend.snapshot()
            switch validator.validate(candidate, previous: before, now: now) {
            case let .success(snapshot):
                guard generation == mutationGeneration else {
                    throw CancellationError()
                }
                try validateProfileResult(layout, in: snapshot)
                currentSnapshot = snapshot
                lastKnownGoodSnapshot = snapshot
                lastRejection = nil
                activeProfileID = profile.id
                recordUndoCheckpoint(before, activeProfileID: priorProfileID)
                return snapshot
            case let .failure(reason):
                lastRejection = reason
                throw MenuBarBackendError.invalidSnapshot(reason)
            }
        } catch {
            if await backend.capabilities.canRestore {
                _ = try? await backend.restore(before)
            }
            currentSnapshot = before
            lastKnownGoodSnapshot = before
            activeProfileID = priorProfileID
            throw error
        }
    }

    private func acquireMutationTurn() async {
        guard mutationIsActive else {
            mutationIsActive = true
            return
        }

        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func releaseMutationTurn() {
        guard !mutationWaiters.isEmpty else {
            mutationIsActive = false
            return
        }
        mutationWaiters.removeFirst().resume()
    }

    public func recover(now: Date = Date()) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        mutationGeneration &+= 1
        backendHealth = MenuBarBackendHealth(backendName: "XPC", state: .restarting)
        await backend.restart()
        if let lastKnownGoodSnapshot, await backend.capabilities.canRestore {
            _ = try await backend.restore(lastKnownGoodSnapshot)
        }
        return try await refreshAssumingMutationTurn(now: now)
    }

    public var canUndo: Bool {
        !undoCheckpoints.isEmpty
    }

    public var canRedo: Bool {
        !redoCheckpoints.isEmpty
    }

    /// Clears profile identity without claiming that the current layout or
    /// workspace settings still correspond to a saved profile.
    public func clearActiveProfileAuthority() async {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }
        activeProfileID = nil
    }

    @discardableResult
    public func undo(now: Date = Date()) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        guard let target = undoCheckpoints.last else {
            throw MenuBarBackendError.operationFailed("no layout undo checkpoint")
        }
        let before = try await HistoryCheckpoint(
            snapshot: validatedStartingSnapshot(now: now),
            activeProfileID: activeProfileID
        )
        let restored = try await restoreHistoryCheckpoint(target, previous: before, now: now)
        undoCheckpoints.removeLast()
        redoCheckpoints.append(before)
        trimHistory(&redoCheckpoints)
        return restored
    }

    @discardableResult
    public func redo(now: Date = Date()) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        guard let target = redoCheckpoints.last else {
            throw MenuBarBackendError.operationFailed("no layout redo checkpoint")
        }
        let before = try await HistoryCheckpoint(
            snapshot: validatedStartingSnapshot(now: now),
            activeProfileID: activeProfileID
        )
        let restored = try await restoreHistoryCheckpoint(target, previous: before, now: now)
        redoCheckpoints.removeLast()
        undoCheckpoints.append(before)
        trimHistory(&undoCheckpoints)
        return restored
    }

    private func restoreHistoryCheckpoint(
        _ target: HistoryCheckpoint,
        previous: HistoryCheckpoint,
        now: Date
    ) async throws -> MenuBarSnapshot {
        guard await backend.capabilities.canRestore else {
            throw MenuBarBackendError.unavailableCapability("restore")
        }
        mutationGeneration &+= 1
        do {
            _ = try await backend.restore(target.snapshot)
            let candidate = try await backend.snapshot()
            // History restoration intentionally targets an older logical layout;
            // structural validation remains strict, but monotonic comparison with
            // the newer pre-undo snapshot would reject a correct restore.
            switch validator.validate(candidate, previous: nil, now: now) {
            case let .success(snapshot):
                try validateHistoryResult(snapshot, matches: target.snapshot)
                currentSnapshot = snapshot
                lastKnownGoodSnapshot = snapshot
                lastRejection = nil
                activeProfileID = target.activeProfileID
                return snapshot
            case let .failure(reason):
                lastRejection = reason
                throw MenuBarBackendError.invalidSnapshot(reason)
            }
        } catch {
            let historyRestoreError = error
            do {
                _ = try await backend.restore(previous.snapshot)
                let rollbackCandidate = try await backend.snapshot()
                let rollbackSnapshot: MenuBarSnapshot
                switch validator.validate(rollbackCandidate, previous: nil, now: now) {
                case let .success(snapshot):
                    try validateHistoryResult(snapshot, matches: previous.snapshot)
                    rollbackSnapshot = snapshot
                case let .failure(reason):
                    throw MenuBarBackendError.invalidSnapshot(reason)
                }
                currentSnapshot = rollbackSnapshot
                lastKnownGoodSnapshot = rollbackSnapshot
                activeProfileID = previous.activeProfileID
            } catch {
                currentSnapshot = nil
                activeProfileID = nil
                throw MenuBarBackendError.operationFailed(
                    "history restore failed: \(historyRestoreError); rollback failed: \(error)"
                )
            }
            throw historyRestoreError
        }
    }

    private func validateHistoryResult(
        _ snapshot: MenuBarSnapshot,
        matches target: MenuBarSnapshot
    ) throws {
        let restoredLayout = Set(snapshot.items.map {
            LogicalLayoutItem(id: $0.id, section: $0.section, order: $0.order)
        })
        let targetLayout = Set(target.items.map {
            LogicalLayoutItem(id: $0.id, section: $0.section, order: $0.order)
        })
        guard restoredLayout == targetLayout else {
            throw MenuBarBackendError.operationFailed(
                "history restore did not reach requested layout"
            )
        }
    }

    private func recordUndoCheckpoint(
        _ snapshot: MenuBarSnapshot,
        activeProfileID: UUID?
    ) {
        undoCheckpoints.append(
            HistoryCheckpoint(snapshot: snapshot, activeProfileID: activeProfileID)
        )
        trimHistory(&undoCheckpoints)
        redoCheckpoints.removeAll(keepingCapacity: true)
    }

    private func trimHistory(_ history: inout [HistoryCheckpoint]) {
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    private func validateReferences(
        for mutation: MenuBarMutation,
        in snapshot: MenuBarSnapshot
    ) throws {
        let itemID: MenuBarItemID? = switch mutation {
        case let .move(operation):
            operation.itemID
        case let .reveal(referencedItemID), let .activate(referencedItemID, _):
            referencedItemID
        case .restoreLastKnownGood:
            nil
        }

        if let itemID, !snapshot.items.contains(where: { $0.id == itemID }) {
            throw MenuBarBackendError.staleItem(itemID)
        }
    }

    private func validatedStartingSnapshot(now: Date) async throws -> MenuBarSnapshot {
        if let currentSnapshot {
            return currentSnapshot
        }
        return try await refreshAssumingMutationTurn(now: now)
    }

    private func requireCurrentGeneration(_ expectedGeneration: UInt64) throws {
        guard currentSnapshot?.generation == expectedGeneration else {
            throw MenuBarAuthorityRefreshError.staleGeneration(
                expected: expectedGeneration,
                actual: currentSnapshot?.generation
            )
        }
    }

    private func apply(_ mutation: MenuBarMutation) async throws {
        switch mutation {
        case let .move(operation):
            _ = try await backend.move(operation)
        case let .reveal(itemID):
            _ = try await backend.reveal(itemID)
        case let .activate(itemID, button):
            try await backend.activate(itemID, button: button)
        case .restoreLastKnownGood:
            guard let lastKnownGoodSnapshot else {
                throw MenuBarBackendError.operationFailed("no last-known-good snapshot")
            }
            _ = try await backend.restore(lastKnownGoodSnapshot)
        }
    }
}
