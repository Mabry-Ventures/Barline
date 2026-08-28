//
//  MenuBarServiceCodecTests.swift
//  Barline
//

@testable import BarlineCore
import Foundation
import Testing

@Suite("Typed menu service codec")
struct MenuBarServiceCodecTests {
    private let itemID = MenuBarItemID(
        bundleIdentifier: "com.example.status",
        accessibilityIdentifier: "primary-status-item"
    )

    @Test("Every typed request survives a Codable round trip")
    func requestRoundTrips() throws {
        let snapshot = makeCodecSnapshot()
        let operation = MenuBarMoveOperation(itemID: itemID, section: .hidden, index: 2)
        let requests: [MenuBarServiceRequest] = [
            .start,
            .capabilities,
            .snapshot,
            .move(operation),
            .reveal(itemID),
            .activate(itemID, .right),
            .restore(snapshot),
            .health,
            .restart,
        ]

        for request in requests {
            let decoded = try JSONDecoder().decode(
                MenuBarServiceRequest.self,
                from: JSONEncoder().encode(request)
            )
            #expect(decoded == request)
        }
    }

    @Test("Every typed response survives a Codable round trip")
    func responseRoundTrips() throws {
        let capabilities = MenuBarCapabilities(
            canSnapshot: true,
            canMove: true,
            canReveal: false,
            canActivate: true,
            canRestore: true
        )
        let snapshot = makeCodecSnapshot()
        let responses: [MenuBarServiceResponse] = [
            .acknowledged,
            .capabilities(capabilities),
            .snapshot(snapshot),
            .mutation(MenuBarMutationResult(generation: 8, changedItemIDs: [itemID])),
            .health(MenuBarBackendHealth(backendName: "Tahoe", state: .degraded, message: "probe")),
            .failure(.interrupted),
        ]

        for response in responses {
            let decoded = try JSONDecoder().decode(
                MenuBarServiceResponse.self,
                from: JSONEncoder().encode(response)
            )
            #expect(decoded == response)
        }
    }

    @Test("Every backend failure keeps its associated data across the wire")
    func errorRoundTrips() throws {
        let errors: [MenuBarBackendError] = [
            .unavailableCapability("move"),
            .staleItem(itemID),
            .unsafeMenuTracking,
            .invalidSnapshot(.nonMonotonicGeneration(previous: 9, candidate: 8)),
            .interrupted,
            .timedOut,
            .operationFailed("probe rejected"),
        ]

        for error in errors {
            let decoded = try JSONDecoder().decode(
                MenuBarBackendError.self,
                from: JSONEncoder().encode(error)
            )
            #expect(decoded == error)

            let response = MenuBarServiceResponse.failure(error)
            let decodedResponse = try JSONDecoder().decode(
                MenuBarServiceResponse.self,
                from: JSONEncoder().encode(response)
            )
            #expect(decodedResponse == response)
        }
    }

    private func makeCodecSnapshot() -> MenuBarSnapshot {
        let displayID = MenuBarDisplayID("built-in")
        return MenuBarSnapshot(
            generation: 7,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            items: [
                MenuBarItemDescriptor(
                    id: itemID,
                    section: .visible,
                    order: 0,
                    displayID: displayID
                ),
            ],
            displayIDs: [displayID],
            activeSpaceIsValid: true
        )
    }
}
