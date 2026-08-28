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
    public let canCapture: Bool

    public init(
        canSnapshot: Bool,
        canMove: Bool,
        canReveal: Bool,
        canActivate: Bool,
        canRestore: Bool,
        canCapture: Bool = false
    ) {
        self.canSnapshot = canSnapshot
        self.canMove = canMove
        self.canReveal = canReveal
        self.canActivate = canActivate
        self.canRestore = canRestore
        self.canCapture = canCapture
    }

    public static let fallback = MenuBarCapabilities(
        canSnapshot: false,
        canMove: false,
        canReveal: false,
        canActivate: false,
        canRestore: false,
        canCapture: false
    )
}

public struct MenuBarCapturedImage: Codable, Equatable, Sendable {
    public let itemID: MenuBarItemID
    public let pngData: Data
    public let bounds: MenuBarRect

    public init(itemID: MenuBarItemID, pngData: Data, bounds: MenuBarRect) {
        self.itemID = itemID
        self.pngData = pngData
        self.bounds = bounds
    }
}

public struct MenuBarBackgroundCapture: Codable, Equatable, Sendable {
    public let displayID: UInt32
    public let menuBarBounds: MenuBarRect
    public let pngData: Data?

    public init(displayID: UInt32, menuBarBounds: MenuBarRect, pngData: Data?) {
        self.displayID = displayID
        self.menuBarBounds = menuBarBounds
        self.pngData = pngData
    }
}

public struct MenuBarPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct MenuBarEnvironmentSnapshot: Codable, Equatable, Sendable {
    public let activeDisplayID: UInt32?
    public let activeStableDisplayID: MenuBarDisplayID?
    public let activeSpaceToken: Int
    public let activeSpaceIsFullscreen: Bool

    public init(
        activeDisplayID: UInt32?,
        activeStableDisplayID: MenuBarDisplayID? = nil,
        activeSpaceToken: Int,
        activeSpaceIsFullscreen: Bool
    ) {
        self.activeDisplayID = activeDisplayID
        self.activeStableDisplayID = activeStableDisplayID
        self.activeSpaceToken = activeSpaceToken
        self.activeSpaceIsFullscreen = activeSpaceIsFullscreen
    }
}

public struct MenuBarPointContext: Codable, Equatable, Sendable {
    public let isInsideMenuBarItem: Bool
    public let applicationBundleIdentifier: String?
    public let applicationIsActive: Bool
    public let applicationUsesRegularActivationPolicy: Bool

    public init(
        isInsideMenuBarItem: Bool,
        applicationBundleIdentifier: String?,
        applicationIsActive: Bool,
        applicationUsesRegularActivationPolicy: Bool
    ) {
        self.isInsideMenuBarItem = isInsideMenuBarItem
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.applicationIsActive = applicationIsActive
        self.applicationUsesRegularActivationPolicy = applicationUsesRegularActivationPolicy
    }
}

public struct MenuBarRevealObservationToken: Codable, Equatable, Hashable, Sendable {
    public let value: UUID

    public init(value: UUID = UUID()) {
        self.value = value
    }
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
    case capture([MenuBarItemID])
    case captureBackground(displayID: UInt32, sampleHeight: Double?)
    case environment
    case configureCursorInBackground(Bool)
    case pointContext(MenuBarPoint)
    case beginRevealObservation(MenuBarItemID)
    case revealObservationIsVisible(MenuBarRevealObservationToken)
    case endRevealObservation(MenuBarRevealObservationToken)
    case restore(MenuBarSnapshot)
    case health
    case restart
}

public enum MenuBarServiceResponse: Codable, Equatable, Sendable {
    case acknowledged
    case capabilities(MenuBarCapabilities)
    case snapshot(MenuBarSnapshot)
    case mutation(MenuBarMutationResult)
    case capturedImages([MenuBarCapturedImage])
    case background(MenuBarBackgroundCapture)
    case environment(MenuBarEnvironmentSnapshot)
    case pointContext(MenuBarPointContext)
    case revealObservation(MenuBarRevealObservationToken)
    case boolean(Bool)
    case health(MenuBarBackendHealth)
    case failure(MenuBarBackendError)
}

public protocol MenuBarBackend: Sendable {
    var capabilities: MenuBarCapabilities { get async }

    func snapshot() async throws -> MenuBarSnapshot
    func move(_ operation: MenuBarMoveOperation) async throws -> MenuBarMutationResult
    func reveal(_ item: MenuBarItemID) async throws -> MenuBarMutationResult
    func activate(_ item: MenuBarItemID, button: MenuBarMouseButton) async throws
    func capture(_ items: [MenuBarItemID]) async throws -> [MenuBarCapturedImage]
    func captureBackground(displayID: UInt32, sampleHeight: Double?) async throws -> MenuBarBackgroundCapture
    func environment() async throws -> MenuBarEnvironmentSnapshot
    func pointContext(_ point: MenuBarPoint) async throws -> MenuBarPointContext
    func beginRevealObservation(_ item: MenuBarItemID) async throws -> MenuBarRevealObservationToken
    func revealObservationIsVisible(_ token: MenuBarRevealObservationToken) async throws -> Bool
    func endRevealObservation(_ token: MenuBarRevealObservationToken) async
    func restore(_ snapshot: MenuBarSnapshot) async throws -> MenuBarMutationResult
    func health() async -> MenuBarBackendHealth
    func restart() async
}

public extension MenuBarBackend {
    func capture(_: [MenuBarItemID]) async throws -> [MenuBarCapturedImage] {
        throw MenuBarBackendError.unavailableCapability("capture")
    }

    func captureBackground(displayID _: UInt32, sampleHeight _: Double?) async throws -> MenuBarBackgroundCapture {
        throw MenuBarBackendError.unavailableCapability("background capture")
    }

    func environment() async throws -> MenuBarEnvironmentSnapshot {
        throw MenuBarBackendError.unavailableCapability("environment")
    }

    func pointContext(_: MenuBarPoint) async throws -> MenuBarPointContext {
        throw MenuBarBackendError.unavailableCapability("point context")
    }

    func beginRevealObservation(_: MenuBarItemID) async throws -> MenuBarRevealObservationToken {
        throw MenuBarBackendError.unavailableCapability("reveal observation")
    }

    func revealObservationIsVisible(_: MenuBarRevealObservationToken) async throws -> Bool {
        false
    }

    func endRevealObservation(_: MenuBarRevealObservationToken) async {}
}
