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

public struct MenuBarWorkspaceCheckpoint: Codable, Hashable, Sendable {
    public let snapshot: MenuBarSnapshot
    public let activeProfileID: UUID?
    public let activeDisplayID: MenuBarDisplayID?
    public let workspace: ProfileWorkspaceState

    public init(
        snapshot: MenuBarSnapshot,
        activeProfileID: UUID?,
        activeDisplayID: MenuBarDisplayID? = nil,
        workspace: ProfileWorkspaceState
    ) {
        self.snapshot = snapshot
        self.activeProfileID = activeProfileID
        self.activeDisplayID = activeDisplayID
        self.workspace = workspace
    }
}

public struct MenuBarWorkspaceTransaction: Sendable {
    fileprivate let captureClosure: @Sendable () async throws -> ProfileWorkspaceState
    fileprivate let applyClosure: @Sendable (ProfileWorkspaceState) async throws -> Void

    public init(
        capture: @escaping @Sendable () async throws -> ProfileWorkspaceState,
        apply: @escaping @Sendable (ProfileWorkspaceState) async throws -> Void
    ) {
        captureClosure = capture
        applyClosure = apply
    }

    fileprivate func capture() async throws -> ProfileWorkspaceState {
        try await captureClosure()
    }

    fileprivate func apply(_ workspace: ProfileWorkspaceState) async throws {
        try await applyClosure(workspace)
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
        let workspace: ProfileWorkspaceState?
    }

    private struct LogicalLayoutItem: Hashable, Sendable {
        let id: MenuBarItemID
        let displayID: MenuBarDisplayID?
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
    private var backendGenerationOffset: UInt64 = 0

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
                let candidate = try await normalizedBackendSnapshot()
                switch validator.validate(candidate, previous: currentSnapshot, now: now) {
                case let .success(snapshot):
                    if let currentSnapshot,
                       logicalLayout(of: currentSnapshot) != logicalLayout(of: snapshot)
                    {
                        activeProfileID = nil
                    }
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
            let candidate = try await normalizedBackendSnapshot()
            switch validator.validate(candidate, previous: before, now: now) {
            case let .success(snapshot):
                guard generation == mutationGeneration else {
                    throw CancellationError()
                }
                if case let .move(operation) = mutation,
                   !MenuBarMovePlanner().resultMatches(operation, in: snapshot)
                {
                    throw MenuBarBackendError.operationFailed(
                        "menu bar move did not reach requested section"
                    )
                }
                if case let .reveal(itemID) = mutation {
                    guard let beforeItem = before.items.first(where: { $0.id == itemID }),
                          let revealedItem = snapshot.items.first(where: { $0.id == itemID }),
                          revealedItem.section == .visible,
                          revealedItem.isOnScreen,
                          revealedItem.displayID == beforeItem.displayID
                    else {
                        throw MenuBarBackendError.operationFailed(
                            "menu bar reveal did not produce a visible item on the requested display"
                        )
                    }
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
            let mutationError = error
            guard await backend.capabilities.canRestore else {
                currentSnapshot = nil
                activeProfileID = nil
                throw mutationError
            }
            do {
                _ = try await backend.restore(before)
                let rollbackCandidate = try await normalizedBackendSnapshot()
                let rollbackSnapshot: MenuBarSnapshot
                switch validator.validate(rollbackCandidate, previous: nil, now: now) {
                case let .success(snapshot):
                    try validateHistoryResult(snapshot, matches: before)
                    rollbackSnapshot = snapshot
                case let .failure(reason):
                    throw MenuBarBackendError.invalidSnapshot(reason)
                }
                currentSnapshot = rollbackSnapshot
                lastKnownGoodSnapshot = rollbackSnapshot
            } catch {
                let rollbackError = error
                currentSnapshot = nil
                activeProfileID = nil
                throw MenuBarBackendError.operationFailed(
                    "mutation failed: \(mutationError); rollback failed: \(rollbackError)"
                )
            }
            throw mutationError
        }
    }

    private func validateProfileResult(
        _ layout: ProfileLayout,
        in snapshot: MenuBarSnapshot,
        displayID: MenuBarDisplayID?
    ) throws {
        for (section, itemIDs) in [
            (MenuBarSection.visible, layout.visible),
            (.hidden, layout.hidden),
            (.alwaysHidden, layout.alwaysHidden),
        ] {
            let actualItemIDs = snapshot.items
                .filter {
                    $0.section == section && (displayID == nil || $0.displayID == displayID)
                }
                .map(\.id)
            guard actualItemIDs.starts(with: itemIDs) else {
                throw MenuBarBackendError.operationFailed(
                    "profile activation did not reach requested layout"
                )
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
        expectedGeneration: UInt64? = nil,
        workspaceTransaction: MenuBarWorkspaceTransaction? = nil,
        prepareCheckpoint: (@Sendable (MenuBarWorkspaceCheckpoint) async throws -> Void)? = nil
    ) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        try Task.checkCancellation()
        if let expectedGeneration {
            try requireCurrentGeneration(expectedGeneration)
        }
        try ProfileValidator().validate(profile)
        let workspaceBefore = try await workspaceTransaction?.capture()
        let startingCheckpoint: HistoryCheckpoint
        if workspaceTransaction != nil {
            startingCheckpoint = try await refreshedHistoryStartingCheckpoint(
                workspace: workspaceBefore,
                now: now
            )
        } else {
            let snapshot = try await validatedStartingSnapshot(now: now)
            startingCheckpoint = HistoryCheckpoint(
                snapshot: snapshot,
                activeProfileID: activeProfileID,
                workspace: workspaceBefore
            )
        }
        let before = startingCheckpoint.snapshot
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
        if let activeDisplayID, !before.displayIDs.contains(activeDisplayID) {
            throw MenuBarBackendError.operationFailed("requested profile display is unavailable")
        }
        let layout = profile.layout(for: activeDisplayID)
        let knownItemIDs = Set(before.items.map(\.id))
        for itemID in layout.allItemIDs where !knownItemIDs.contains(itemID) {
            throw MenuBarBackendError.staleItem(itemID)
        }

        let priorProfileID = startingCheckpoint.activeProfileID
        if let prepareCheckpoint {
            guard let workspaceBefore else {
                throw MenuBarBackendError.operationFailed(
                    "checkpoint preparation requires a workspace transaction"
                )
            }
            try await prepareCheckpoint(
                MenuBarWorkspaceCheckpoint(
                    snapshot: before,
                    activeProfileID: priorProfileID,
                    activeDisplayID: activeDisplayID,
                    workspace: workspaceBefore
                )
            )
        }
        let targetWorkspace = ProfileWorkspaceState(profile: profile)
        mutationGeneration &+= 1
        let generation = mutationGeneration
        var didBeginLayoutMutation = false
        var didBeginWorkspaceMutation = false

        do {
            if let workspaceTransaction {
                didBeginWorkspaceMutation = true
                try await workspaceTransaction.apply(targetWorkspace)
            }
            for (section, itemIDs) in [
                (MenuBarSection.visible, layout.visible),
                (.hidden, layout.hidden),
                (.alwaysHidden, layout.alwaysHidden),
            ] {
                let sectionCandidates = before.items.filter { $0.section == section }
                let baseIndex = activeDisplayID.flatMap { displayID in
                    sectionCandidates.firstIndex(where: { $0.displayID == displayID })
                } ?? 0
                for (index, itemID) in itemIDs.enumerated() {
                    didBeginLayoutMutation = true
                    _ = try await backend.move(
                        MenuBarMoveOperation(
                            itemID: itemID,
                            section: section,
                            index: baseIndex + index,
                            destinationDisplayID: activeDisplayID
                        )
                    )
                }
            }

            try Task.checkCancellation()
            let candidate = try await normalizedBackendSnapshot()
            switch validator.validate(candidate, previous: before, now: now) {
            case let .success(snapshot):
                guard generation == mutationGeneration else {
                    throw CancellationError()
                }
                try validateProfileResult(layout, in: snapshot, displayID: activeDisplayID)
                currentSnapshot = snapshot
                lastKnownGoodSnapshot = snapshot
                lastRejection = nil
                activeProfileID = profile.id
                recordUndoCheckpoint(
                    before,
                    activeProfileID: priorProfileID,
                    workspace: workspaceBefore
                )
                return snapshot
            case let .failure(reason):
                lastRejection = reason
                throw MenuBarBackendError.invalidSnapshot(reason)
            }
        } catch {
            let activationError = error
            var workspaceRollbackError: (any Error)?
            var layoutRollbackError: (any Error)?
            var verifiedRollbackSnapshot: MenuBarSnapshot?
            if let workspaceBefore, let workspaceTransaction {
                do {
                    try await workspaceTransaction.apply(workspaceBefore)
                } catch {
                    workspaceRollbackError = error
                }
            }
            if didBeginLayoutMutation || didBeginWorkspaceMutation {
                if await backend.capabilities.canRestore {
                    do {
                        _ = try await backend.restore(before)
                        let candidate = try await normalizedBackendSnapshot()
                        switch validator.validate(candidate, previous: nil, now: now) {
                        case let .success(snapshot):
                            try validateHistoryResult(snapshot, matches: before)
                            verifiedRollbackSnapshot = snapshot
                        case let .failure(reason):
                            throw MenuBarBackendError.invalidSnapshot(reason)
                        }
                    } catch {
                        layoutRollbackError = error
                    }
                } else {
                    layoutRollbackError = MenuBarBackendError.unavailableCapability("restore")
                }
            } else {
                verifiedRollbackSnapshot = before
            }
            if workspaceRollbackError == nil,
               layoutRollbackError == nil,
               let verifiedRollbackSnapshot
            {
                currentSnapshot = verifiedRollbackSnapshot
                lastKnownGoodSnapshot = verifiedRollbackSnapshot
                activeProfileID = priorProfileID
                throw activationError
            }
            currentSnapshot = nil
            activeProfileID = nil
            let workspaceDescription = workspaceRollbackError.map(String.init(describing:)) ?? "none"
            let layoutDescription = layoutRollbackError.map(String.init(describing:)) ?? "none"
            throw MenuBarBackendError.operationFailed(
                "profile activation failed: \(activationError); workspace rollback: \(workspaceDescription); layout rollback: \(layoutDescription)"
            )
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

    public func recover(now: Date? = nil) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        let preservedCurrent = currentSnapshot
        let preservedLastKnownGood = lastKnownGoodSnapshot
        mutationGeneration &+= 1
        backendHealth = MenuBarBackendHealth(backendName: "XPC", state: .restarting)
        await backend.restart()

        do {
            let restoredLastKnownGood: Bool
            if let preservedLastKnownGood, await backend.capabilities.canRestore {
                _ = try await backend.restore(preservedLastKnownGood)
                restoredLastKnownGood = true
            } else {
                restoredLastKnownGood = false
            }
            let raw = try await backend.snapshot()
            let priorGeneration = max(
                preservedCurrent?.generation ?? 0,
                preservedLastKnownGood?.generation ?? 0
            )
            if raw.generation <= priorGeneration {
                let (nextGeneration, overflowed) = priorGeneration.addingReportingOverflow(1)
                guard !overflowed else {
                    throw MenuBarBackendError.operationFailed("helper generation rebase overflow")
                }
                backendGenerationOffset = nextGeneration - raw.generation
            } else {
                backendGenerationOffset = 0
            }
            let candidate = try normalizeGeneration(of: raw)
            let continuityBaseline = preservedCurrent ?? preservedLastKnownGood
            let validationNow = now ?? Date()
            switch validator.validate(candidate, previous: continuityBaseline, now: validationNow) {
            case let .success(snapshot):
                if restoredLastKnownGood, let preservedLastKnownGood {
                    try validateHistoryResult(snapshot, matches: preservedLastKnownGood)
                } else if let continuityBaseline,
                          logicalLayout(of: snapshot) != logicalLayout(of: continuityBaseline)
                {
                    activeProfileID = nil
                }
                currentSnapshot = snapshot
                lastKnownGoodSnapshot = snapshot
                lastRejection = nil
                backendHealth = await backend.health()
                return snapshot
            case let .failure(reason):
                lastRejection = reason
                throw MenuBarBackendError.invalidSnapshot(reason)
            }
        } catch {
            currentSnapshot = nil
            lastKnownGoodSnapshot = preservedLastKnownGood
            activeProfileID = nil
            backendGenerationOffset = 0
            throw error
        }
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
    public func clearActiveProfileAuthority(ifMatches profileID: UUID) async -> Bool {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }
        guard activeProfileID == profileID else { return false }
        activeProfileID = nil
        return true
    }

    public func captureWorkspaceCheckpoint(
        workspaceTransaction: MenuBarWorkspaceTransaction,
        now: Date = Date()
    ) async throws -> MenuBarWorkspaceCheckpoint {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }
        let snapshot = try await refreshAssumingMutationTurn(now: now)
        let workspace = try await workspaceTransaction.capture()
        let activeDisplayID: MenuBarDisplayID? = if let environment = try? await backend.environment(),
                                                    let displayID = environment.activeStableDisplayID,
                                                    snapshot.displayIDs.contains(displayID)
        {
            displayID
        } else {
            nil
        }
        return MenuBarWorkspaceCheckpoint(
            snapshot: snapshot,
            activeProfileID: activeProfileID,
            activeDisplayID: activeDisplayID,
            workspace: workspace
        )
    }

    @discardableResult
    public func restoreWorkspaceCheckpoint(
        _ checkpoint: MenuBarWorkspaceCheckpoint,
        workspaceTransaction: MenuBarWorkspaceTransaction,
        now: Date = Date()
    ) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }
        try ProfileValidator().validate(checkpoint.workspace)
        switch validator.validate(
            checkpoint.snapshot,
            previous: nil,
            now: checkpoint.snapshot.capturedAt
        ) {
        case .success:
            break
        case let .failure(reason):
            throw MenuBarBackendError.invalidSnapshot(reason)
        }
        let live = try await refreshedHistoryStartingCheckpoint(
            workspace: workspaceTransaction.capture(),
            now: now
        )
        let target = HistoryCheckpoint(
            snapshot: checkpoint.snapshot,
            activeProfileID: checkpoint.activeProfileID,
            workspace: checkpoint.workspace
        )
        let restored = try await restoreHistoryCheckpoint(
            target,
            previous: live,
            now: now,
            workspaceTransaction: workspaceTransaction
        )
        recordUndoCheckpoint(
            live.snapshot,
            activeProfileID: live.activeProfileID,
            workspace: live.workspace
        )
        return restored
    }

    @discardableResult
    public func undo(
        now: Date = Date(),
        workspaceTransaction: MenuBarWorkspaceTransaction? = nil
    ) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        guard let target = undoCheckpoints.last else {
            throw MenuBarBackendError.operationFailed("no layout undo checkpoint")
        }
        let before = try await refreshedHistoryStartingCheckpoint(
            workspace: workspaceTransaction?.capture(),
            now: now
        )
        let restored = try await restoreHistoryCheckpoint(
            target,
            previous: before,
            now: now,
            workspaceTransaction: workspaceTransaction
        )
        undoCheckpoints.removeLast()
        redoCheckpoints.append(before)
        trimHistory(&redoCheckpoints)
        return restored
    }

    @discardableResult
    public func redo(
        now: Date = Date(),
        workspaceTransaction: MenuBarWorkspaceTransaction? = nil
    ) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        guard let target = redoCheckpoints.last else {
            throw MenuBarBackendError.operationFailed("no layout redo checkpoint")
        }
        let before = try await refreshedHistoryStartingCheckpoint(
            workspace: workspaceTransaction?.capture(),
            now: now
        )
        let restored = try await restoreHistoryCheckpoint(
            target,
            previous: before,
            now: now,
            workspaceTransaction: workspaceTransaction
        )
        redoCheckpoints.removeLast()
        undoCheckpoints.append(before)
        trimHistory(&undoCheckpoints)
        return restored
    }

    private func restoreHistoryCheckpoint(
        _ target: HistoryCheckpoint,
        previous: HistoryCheckpoint,
        now: Date,
        workspaceTransaction: MenuBarWorkspaceTransaction? = nil
    ) async throws -> MenuBarSnapshot {
        guard await backend.capabilities.canRestore else {
            throw MenuBarBackendError.unavailableCapability("restore")
        }
        if target.workspace != nil, workspaceTransaction == nil {
            throw MenuBarBackendError.operationFailed(
                "workspace history requires a rollback-capable transaction"
            )
        }
        mutationGeneration &+= 1
        do {
            if let workspace = target.workspace, let workspaceTransaction {
                try await workspaceTransaction.apply(workspace)
            }
            _ = try await backend.restore(target.snapshot)
            let candidate = try await normalizedBackendSnapshot()
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
                if let workspace = previous.workspace, let workspaceTransaction {
                    try await workspaceTransaction.apply(workspace)
                }
                _ = try await backend.restore(previous.snapshot)
                let rollbackCandidate = try await normalizedBackendSnapshot()
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
        guard snapshot.displayIDs == target.displayIDs else {
            throw MenuBarBackendError.operationFailed(
                "history restore did not reach requested displays"
            )
        }
        let restoredLayout = Set(snapshot.items.map {
            LogicalLayoutItem(
                id: $0.id,
                displayID: $0.displayID,
                section: $0.section,
                order: $0.order
            )
        })
        let targetLayout = Set(target.items.map {
            LogicalLayoutItem(
                id: $0.id,
                displayID: $0.displayID,
                section: $0.section,
                order: $0.order
            )
        })
        guard restoredLayout == targetLayout else {
            throw MenuBarBackendError.operationFailed(
                "history restore did not reach requested layout"
            )
        }
    }

    private func recordUndoCheckpoint(
        _ snapshot: MenuBarSnapshot,
        activeProfileID: UUID?,
        workspace: ProfileWorkspaceState? = nil
    ) {
        undoCheckpoints.append(
            HistoryCheckpoint(
                snapshot: snapshot,
                activeProfileID: activeProfileID,
                workspace: workspace
            )
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

    private func refreshedHistoryStartingCheckpoint(
        workspace: ProfileWorkspaceState?,
        now: Date
    ) async throws -> HistoryCheckpoint {
        let cached = currentSnapshot
        let live = try await refreshAssumingMutationTurn(now: now)
        if let cached, logicalLayout(of: cached) != logicalLayout(of: live) {
            activeProfileID = nil
        }
        return HistoryCheckpoint(
            snapshot: live,
            activeProfileID: activeProfileID,
            workspace: workspace
        )
    }

    private func logicalLayout(of snapshot: MenuBarSnapshot) -> Set<LogicalLayoutItem> {
        Set(snapshot.items.map {
            LogicalLayoutItem(
                id: $0.id,
                displayID: $0.displayID,
                section: $0.section,
                order: $0.order
            )
        })
    }

    private func normalizedBackendSnapshot() async throws -> MenuBarSnapshot {
        try await normalizeGeneration(of: backend.snapshot())
    }

    private func normalizeGeneration(of snapshot: MenuBarSnapshot) throws -> MenuBarSnapshot {
        let (generation, overflowed) = snapshot.generation.addingReportingOverflow(
            backendGenerationOffset
        )
        guard !overflowed else {
            throw MenuBarBackendError.operationFailed("helper generation normalization overflow")
        }
        guard backendGenerationOffset != 0 else { return snapshot }
        return MenuBarSnapshot(
            generation: generation,
            capturedAt: snapshot.capturedAt,
            items: snapshot.items,
            displayIDs: snapshot.displayIDs,
            activeSpaceIsValid: snapshot.activeSpaceIsValid,
            menuTrackingIsActive: snapshot.menuTrackingIsActive
        )
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
