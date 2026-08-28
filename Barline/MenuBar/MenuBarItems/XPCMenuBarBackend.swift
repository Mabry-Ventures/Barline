//
//  XPCMenuBarBackend.swift
//  Barline
//

import BarlineCore
import Foundation

actor XPCMenuBarBackend: MenuBarBackend {
    private let connection = BarlineMenuService.Connection.shared

    var capabilities: MenuBarCapabilities {
        get async {
            await (try? connection.capabilities()) ?? .fallback
        }
    }

    func snapshot() async throws -> MenuBarSnapshot {
        try await connection.snapshot()
    }

    func move(_ operation: MenuBarMoveOperation) async throws -> MenuBarMutationResult {
        try await connection.move(operation)
    }

    func reveal(_ item: MenuBarItemID) async throws -> MenuBarMutationResult {
        try await connection.reveal(item)
    }

    func activate(_ item: MenuBarItemID, button: MenuBarMouseButton) async throws {
        try await connection.activate(item, button: button)
    }

    func restore(_ snapshot: MenuBarSnapshot) async throws -> MenuBarMutationResult {
        try await connection.restore(snapshot)
    }

    func health() async -> MenuBarBackendHealth {
        await connection.health()
    }

    func restart() async {
        await connection.restart()
    }
}
