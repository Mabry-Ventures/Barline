//
//  CompatibilityContracts.swift
//  Barline
//

import Foundation

public struct MenuBarCapabilities: Codable, Equatable, Sendable {
    public let canSnapshot: Bool
    public let canMove: Bool
    public let canReveal: Bool
    public let canActivate: Bool
    public let canRestore: Bool

    public init(
        canSnapshot: Bool,
        canMove: Bool,
        canReveal: Bool,
        canActivate: Bool,
        canRestore: Bool
    ) {
        self.canSnapshot = canSnapshot
        self.canMove = canMove
        self.canReveal = canReveal
        self.canActivate = canActivate
        self.canRestore = canRestore
    }

    public static let fallback = MenuBarCapabilities(
        canSnapshot: false,
        canMove: false,
        canReveal: false,
        canActivate: false,
        canRestore: false
    )
}

public enum MenuBarMouseButton: String, Codable, Sendable {
    case left
    case right
    case other
}

public struct MenuBarMoveOperation: Codable, Equatable, Sendable {
    public let itemID: MenuBarItemID
    public let section: MenuBarSection
    public let index: Int

    public init(itemID: MenuBarItemID, section: MenuBarSection, index: Int) {
        self.itemID = itemID
        self.section = section
        self.index = index
    }
}

public struct MenuBarMutationResult: Codable, Equatable, Sendable {
    public let generation: UInt64
    public let changedItemIDs: [MenuBarItemID]

    public init(generation: UInt64, changedItemIDs: [MenuBarItemID]) {
        self.generation = generation
        self.changedItemIDs = changedItemIDs
    }
}

public enum MenuBarBackendState: String, Codable, Sendable {
    case healthy
    case degraded
    case unavailable
    case restarting
}

public struct MenuBarBackendHealth: Codable, Equatable, Sendable {
    public let backendName: String
    public let state: MenuBarBackendState
    public let message: String?

    public init(backendName: String, state: MenuBarBackendState, message: String? = nil) {
        self.backendName = backendName
        self.state = state
        self.message = message
    }
}

public enum MenuBarBackendError: Error, Codable, Equatable, Sendable {
    case unavailableCapability(String)
    case staleItem(MenuBarItemID)
    case unsafeMenuTracking
    case invalidSnapshot(SnapshotRejectionReason)
    case interrupted
    case timedOut
    case operationFailed(String)
}

/// The complete, domain-typed protocol exchanged with the menu-bar helper.
///
/// Keeping this contract in BarlineCore prevents XPC clients from exposing
/// ephemeral WindowServer identifiers or private framework types.
public enum MenuBarServiceRequest: Codable, Equatable, Sendable {
    case start
    case capabilities
    case snapshot
    case move(MenuBarMoveOperation)
    case reveal(MenuBarItemID)
    case activate(MenuBarItemID, MenuBarMouseButton)
    case restore(MenuBarSnapshot)
    case health
    case restart
}

public enum MenuBarServiceResponse: Codable, Equatable, Sendable {
    case acknowledged
    case capabilities(MenuBarCapabilities)
    case snapshot(MenuBarSnapshot)
    case mutation(MenuBarMutationResult)
    case health(MenuBarBackendHealth)
    case failure(MenuBarBackendError)
}

public protocol MenuBarBackend: Sendable {
    var capabilities: MenuBarCapabilities { get async }

    func snapshot() async throws -> MenuBarSnapshot
    func move(_ operation: MenuBarMoveOperation) async throws -> MenuBarMutationResult
    func reveal(_ item: MenuBarItemID) async throws -> MenuBarMutationResult
    func activate(_ item: MenuBarItemID, button: MenuBarMouseButton) async throws
    func restore(_ snapshot: MenuBarSnapshot) async throws -> MenuBarMutationResult
    func health() async -> MenuBarBackendHealth
    func restart() async
}
