//
//  StateCoordinator.swift
//  Barline
//

import Foundation

public enum MenuBarMutation: Sendable {
    case move(MenuBarMoveOperation)
    case reveal(MenuBarItemID)
    case activate(MenuBarItemID, MenuBarMouseButton)
    case restoreLastKnownGood
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
    private var mutationIsActive = false
    private var mutationWaiters = [CheckedContinuation<Void, Never>]()

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
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        try Task.checkCancellation()
        let before = try await validatedStartingSnapshot(now: now)
        guard !before.menuTrackingIsActive else {
            throw MenuBarBackendError.unsafeMenuTracking
        }
        try validateReferences(for: mutation, in: before)

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
                currentSnapshot = snapshot
                lastKnownGoodSnapshot = snapshot
                lastRejection = nil
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
        now: Date = Date()
    ) async throws -> MenuBarSnapshot {
        await acquireMutationTurn()
        defer { releaseMutationTurn() }

        try Task.checkCancellation()
        try ProfileValidator().validate(profile)
        let before = try await validatedStartingSnapshot(now: now)
        guard !before.menuTrackingIsActive else {
            throw MenuBarBackendError.unsafeMenuTracking
        }

        let layout = profile.layout(for: displayID)
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
        return try await refresh(now: now)
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
        return try await refresh(now: now)
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
