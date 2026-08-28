import BarlineCore
import Foundation

actor TahoeMenuBarBackend: MenuBarBackend {
    let capabilities: MenuBarCapabilities
    private let client: WindowServerClient

    init(client: WindowServerClient) {
        self.client = client
        capabilities = MenuBarCapabilities(
            canSnapshot: client.behavioralProbe(),
            canMove: client.behavioralProbe() && client.eventSynthesisProbe(),
            canReveal: client.behavioralProbe() && client.eventSynthesisProbe(),
            canActivate: client.behavioralProbe() && client.eventSynthesisProbe(),
            canRestore: client.behavioralProbe() && client.eventSynthesisProbe(),
            canCapture: client.behavioralProbe()
        )
    }

    func snapshot() throws -> MenuBarSnapshot {
        guard capabilities.canSnapshot else {
            throw MenuBarBackendError.unavailableCapability("Tahoe snapshot")
        }
        return try client.snapshot()
    }

    func move(_ operation: MenuBarMoveOperation) async throws -> MenuBarMutationResult {
        try await client.move(operation)
    }

    func reveal(_ item: MenuBarItemID) async throws -> MenuBarMutationResult {
        try await client.reveal(item)
    }

    func activate(_ item: MenuBarItemID, button: MenuBarMouseButton) async throws {
        try await client.activate(item, button: button)
    }

    func capture(_ items: [MenuBarItemID]) throws -> [MenuBarCapturedImage] {
        try client.capture(items)
    }

    func captureBackground(
        displayID: UInt32,
        sampleHeight: Double?
    ) throws -> MenuBarBackgroundCapture {
        try client.captureBackground(displayID: displayID, sampleHeight: sampleHeight)
    }

    func environment() -> MenuBarEnvironmentSnapshot {
        client.environment()
    }

    func pointContext(_ point: MenuBarPoint) throws -> MenuBarPointContext {
        try client.pointContext(point)
    }

    func beginRevealObservation(_ item: MenuBarItemID) throws -> MenuBarRevealObservationToken {
        try client.beginRevealObservation(item)
    }

    func revealObservationIsVisible(_ token: MenuBarRevealObservationToken) -> Bool {
        client.revealObservationIsVisible(token)
    }

    func endRevealObservation(_ token: MenuBarRevealObservationToken) {
        client.endRevealObservation(token)
    }

    func restore(_ snapshot: MenuBarSnapshot) async throws -> MenuBarMutationResult {
        try await client.restore(snapshot)
    }

    func health() -> MenuBarBackendHealth {
        MenuBarBackendHealth(
            backendName: "Tahoe",
            state: capabilities.canSnapshot ? .healthy : .unavailable,
            message: capabilities.canSnapshot ? nil : "Required WindowServer probes failed"
        )
    }

    func restart() {}
}

actor GoldenGateMenuBarBackend: MenuBarBackend {
    let capabilities: MenuBarCapabilities
    private let client: WindowServerClient

    init(client: WindowServerClient) {
        self.client = client
        capabilities = MenuBarCapabilities(
            canSnapshot: client.behavioralProbe(),
            canMove: client.behavioralProbe() && client.eventSynthesisProbe(),
            canReveal: client.behavioralProbe() && client.eventSynthesisProbe(),
            canActivate: client.behavioralProbe() && client.eventSynthesisProbe(),
            canRestore: client.behavioralProbe() && client.eventSynthesisProbe(),
            canCapture: client.behavioralProbe()
        )
    }

    func snapshot() throws -> MenuBarSnapshot {
        guard capabilities.canSnapshot else {
            throw MenuBarBackendError.unavailableCapability("Golden Gate snapshot")
        }
        return try client.snapshot()
    }

    func move(_ operation: MenuBarMoveOperation) async throws -> MenuBarMutationResult {
        try await client.move(operation)
    }

    func reveal(_ item: MenuBarItemID) async throws -> MenuBarMutationResult {
        try await client.reveal(item)
    }

    func activate(_ item: MenuBarItemID, button: MenuBarMouseButton) async throws {
        try await client.activate(item, button: button)
    }

    func capture(_ items: [MenuBarItemID]) throws -> [MenuBarCapturedImage] {
        try client.capture(items)
    }

    func captureBackground(
        displayID: UInt32,
        sampleHeight: Double?
    ) throws -> MenuBarBackgroundCapture {
        try client.captureBackground(displayID: displayID, sampleHeight: sampleHeight)
    }

    func environment() -> MenuBarEnvironmentSnapshot {
        client.environment()
    }

    func pointContext(_ point: MenuBarPoint) throws -> MenuBarPointContext {
        try client.pointContext(point)
    }

    func beginRevealObservation(_ item: MenuBarItemID) throws -> MenuBarRevealObservationToken {
        try client.beginRevealObservation(item)
    }

    func revealObservationIsVisible(_ token: MenuBarRevealObservationToken) -> Bool {
        client.revealObservationIsVisible(token)
    }

    func endRevealObservation(_ token: MenuBarRevealObservationToken) {
        client.endRevealObservation(token)
    }

    func restore(_ snapshot: MenuBarSnapshot) async throws -> MenuBarMutationResult {
        try await client.restore(snapshot)
    }

    func health() -> MenuBarBackendHealth {
        MenuBarBackendHealth(
            backendName: "GoldenGate",
            state: capabilities.canSnapshot ? .healthy : .unavailable,
            message: capabilities.canSnapshot ? nil : "Required WindowServer probes failed"
        )
    }

    func restart() {}
}

actor FallbackMenuBarBackend: MenuBarBackend {
    let capabilities = MenuBarCapabilities.fallback

    func snapshot() throws -> MenuBarSnapshot {
        throw MenuBarBackendError.unavailableCapability("menu bar snapshot")
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

    func capture(_: [MenuBarItemID]) throws -> [MenuBarCapturedImage] {
        throw MenuBarBackendError.unavailableCapability("capture")
    }

    func captureBackground(
        displayID _: UInt32,
        sampleHeight _: Double?
    ) throws -> MenuBarBackgroundCapture {
        throw MenuBarBackendError.unavailableCapability("background capture")
    }

    func restore(_: MenuBarSnapshot) throws -> MenuBarMutationResult {
        throw MenuBarBackendError.unavailableCapability("restore")
    }

    func health() -> MenuBarBackendHealth {
        MenuBarBackendHealth(
            backendName: "Fallback",
            state: .unavailable,
            message: "Private compatibility probes are unavailable; safe native features remain accessible"
        )
    }

    func restart() {}
}

enum MenuBarBackendFactory {
    static func make() -> any MenuBarBackend {
        let client = WindowServerClient()

        // Selection is gated by live behavior first. The OS check only
        // determines which implementation gets first opportunity to probe.
        if #available(macOS 27.0, *) {
            let goldenGate = GoldenGateMenuBarBackend(client: client)
            if client.behavioralProbe() {
                return goldenGate
            }
        }

        let tahoe = TahoeMenuBarBackend(client: client)
        if client.behavioralProbe() {
            return tahoe
        }
        return FallbackMenuBarBackend()
    }
}
