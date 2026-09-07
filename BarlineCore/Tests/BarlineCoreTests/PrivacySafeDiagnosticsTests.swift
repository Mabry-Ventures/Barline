@testable import BarlineCore
import Foundation
import Testing

struct PrivacySafeDiagnosticsTests {
    @Test func payloadsAreNeverFormatted() {
        let secret = "PRIVATE_PROFILE_TITLE_/Users/private-person/private-file"
        let item = MenuBarItemID(bundleIdentifier: secret, title: secret)
        let errors: [any Error] = [
            MenuBarBackendError.staleItem(item),
            MenuBarBackendError.operationFailed(secret),
            MenuBarBackendError.unavailableCapability(secret),
            MenuBarBackendError.invalidSnapshot(.unstableItemIdentity(item)),
            NSError(domain: secret, code: 7, userInfo: [
                NSLocalizedDescriptionKey: secret,
                NSUnderlyingErrorKey: MenuBarBackendError.staleItem(item),
            ]),
        ]
        let codes = errors.map { PrivacySafeDiagnostics.errorCode($0) }
        #expect(codes == ["stale_item", "operation_failed", "capability_unavailable",
                          "snapshot_unstable_item", "operation_failed"])
        #expect(!String(describing: codes).contains(secret))
    }

    @Test func collapseFailureRemainsDiagnosableWithoutInventory() {
        #expect(PrivacySafeDiagnostics.errorCode(
            MenuBarBackendError.invalidSnapshot(.implausibleSystemItemCollapse(previous: 15, candidate: 4))
        ) == "snapshot_system_item_collapse")
        #expect(PrivacySafeDiagnostics.errorCode(CancellationError()) == "cancelled")
    }

    @Test func everySnapshotCodeIsClosedAndPayloadFree() {
        let secret = "private_payload"
        let item = MenuBarItemID(bundleIdentifier: secret, title: secret)
        let display = MenuBarDisplayID(secret)
        let reasons: [SnapshotRejectionReason] = [
            .missingDisplayGeometry, .invalidActiveSpace, .staleSnapshot, .futureDatedSnapshot,
            .unknownItemDisplay(display), .displayIdentitySetMismatch, .duplicateDisplayIdentity(display),
            .malformedDisplayFingerprint, .duplicateItemIdentity(item), .unstableItemIdentity(item),
            .invalidItemGeometry(item), .missingRequiredControlItem(item),
            .implausibleItemCountCollapse(previous: 99, candidate: 1),
            .implausibleSystemItemCollapse(previous: 99, candidate: 1), .emptySnapshot,
            .nonMonotonicGeneration(previous: 99, candidate: 1),
        ]
        let codes = reasons.map { PrivacySafeDiagnostics.errorCode(MenuBarBackendError.invalidSnapshot($0)) }
        #expect(Set(codes).count == reasons.count)
        for code in codes {
            #expect(code.hasPrefix("snapshot_"))
            #expect(!code.contains(secret))
            #expect(code.allSatisfy { $0.isLowercase || $0 == "_" })
        }
    }

    @Test func wrappedAndSerializationErrorsDropTheirDescriptions() {
        #expect(PrivacySafeDiagnostics.errorCode(MenuBarBackendError.unsafeMenuTracking) == "menu_tracking_active")
        #expect(PrivacySafeDiagnostics.errorCode(MenuBarBackendError.interrupted) == "helper_interrupted")
        #expect(PrivacySafeDiagnostics.errorCode(MenuBarBackendError.timedOut) == "helper_timed_out")
        #expect(PrivacySafeDiagnostics.errorCode(DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "private file path")
        )) == "decode_failed")
        #expect(PrivacySafeDiagnostics.errorCode(EncodingError.invalidValue(
            "private item title", .init(codingPath: [], debugDescription: "private profile name")
        )) == "encode_failed")
    }
}
