@testable import BarlineCore
import Foundation
import Testing

struct IntentCommandFailurePolicyTests {
    @Test func nativeFocusOwnershipDoesNotDependOnActivationSuccess() {
        #expect(IntentCommandFailurePolicy.requestedFocusState(for: .setFocusProfile(UUID())) == true)
        #expect(IntentCommandFailurePolicy.requestedFocusState(for: .setFocusProfile(nil)) == false)
        #expect(IntentCommandFailurePolicy.requestedFocusState(for: .setPresentationMode(true)) == true)
        #expect(IntentCommandFailurePolicy.requestedFocusState(for: .setPresentationMode(false)) == false)
        #expect(IntentCommandFailurePolicy.requestedFocusState(for: .activateProfile(UUID())) == nil)
        #expect(IntentCommandFailurePolicy.requestedFocusState(for: .open(.search)) == nil)
    }

    @Test func unavailableSavedItemRequiresNewUserDecision() {
        let error = MenuBarBackendError.staleItem(.init(bundleIdentifier: "fixture", title: "item"))
        #expect(IntentCommandFailurePolicy.requiresUserReview(error))
    }

    @Test func transientAndUnknownErrorsKeepExistingRetrySemantics() {
        let errors: [any Error] = [
            MenuBarBackendError.interrupted,
            MenuBarBackendError.timedOut,
            MenuBarBackendError.unsafeMenuTracking,
            MenuBarBackendError.unavailableCapability("fixture"),
            MenuBarBackendError.operationFailed("stale_item"),
            MenuBarWorkspaceTransactionError.sideEffectRecoveryFailed,
            CancellationError(),
        ]
        for error in errors {
            #expect(!IntentCommandFailurePolicy.requiresUserReview(error))
        }
    }
}
