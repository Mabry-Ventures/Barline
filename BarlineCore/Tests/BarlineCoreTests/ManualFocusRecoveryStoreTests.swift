@testable import BarlineCore
import Foundation
import Testing

struct ManualFocusRecoveryStoreTests {
    @Test("Manual receipts survive reopen without becoming active authority or overwriting another checkpoint")
    func manualReceiptLifetime() throws {
        let suite = "BarlineTests.ManualRecovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = BarlineProfile(name: "Test")
        let presentation = ResolvedProfilePresentation(
            source: .base, destinationDisplayID: nil, layout: profile.layout, groups: [], spacers: []
        )
        let checkpoint = MenuBarWorkspaceCheckpoint(
            snapshot: MenuBarSnapshot(
                generation: 1, capturedAt: Date(), items: [], displayIDs: [], activeSpaceIsValid: true
            ), activeProfileID: nil, workspace: ProfileWorkspaceState(profile: profile)
        )
        let value = ProfileAuthorityEnvelope(
            pendingFocusProfile: profile, token: UUID(), presentation: presentation,
            checkpoint: checkpoint, priorAuthority: nil
        )
        let store = ManualFocusRecoveryStore(defaults: defaults, key: "manual")
        try store.archive(value)
        let reopened = ManualFocusRecoveryStore(defaults: defaults, key: "manual")
        #expect(reopened.load() == value)
        #expect(ProfileAuthorityEnvelopeStore(defaults: defaults, key: "active").load() == nil)
        try reopened.archive(value)
        let newer = ProfileAuthorityEnvelope(
            pendingFocusProfile: profile, token: UUID(), presentation: presentation,
            checkpoint: checkpoint, priorAuthority: nil
        )
        #expect(throws: (any Error).self) { try reopened.archive(newer) }
        reopened.remove(ifMatching: newer.token)
        #expect(reopened.load() == value)
        reopened.remove(ifMatching: value.token)
        #expect(reopened.load() == nil)
        defaults.set(Data("malformed".utf8), forKey: "manual")
        #expect(throws: (any Error).self) { try reopened.archive(value) }
        #expect(defaults.data(forKey: "manual") == Data("malformed".utf8))
    }
}
