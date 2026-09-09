@testable import BarlineCore
import Foundation
import Testing

@Suite("Display variant authoring")
struct DisplayVariantCaptureTests {
    let now = Date(timeIntervalSince1970: 1000)
    let display = MenuBarDisplayID("desk")
    let other = MenuBarDisplayID("laptop")
    let item = MenuBarItemID(bundleIdentifier: "com.example.one", accessibilityIdentifier: "one")
    let foreign = MenuBarItemID(bundleIdentifier: "com.example.two", accessibilityIdentifier: "two")

    func snapshot(age: Double = 0, identities: [MenuBarDisplayIdentity]? = nil) -> MenuBarSnapshot {
        MenuBarSnapshot(generation: 1, capturedAt: now.addingTimeInterval(-age), items: [
            MenuBarItemDescriptor(id: item, section: .hidden, order: 0, displayID: display),
            MenuBarItemDescriptor(id: foreign, section: .visible, order: 0, displayID: other),
        ], displayIDs: [display, other], displayIdentities: identities ?? [
            MenuBarDisplayIdentity(runtimeID: display), MenuBarDisplayIdentity(runtimeID: other),
        ], activeSpaceIsValid: true)
    }

    @Test("Capture scopes membership and preserves the base layout")
    func scopedCapture() throws {
        let profile = BarlineProfile(name: "Example", layout: ProfileLayout(visible: [item, foreign]),
                                     groups: [ProfileGroup(name: "Tools", itemIDs: [item, foreign])])
        let variant = try DisplayVariantCapture.capture(profile: profile, snapshot: snapshot(), displayID: display, now: now)
        #expect(variant.layout.hidden == [item])
        #expect(variant.layout.visible.isEmpty)
        #expect(variant.groups.first?.itemIDs == [item])
        #expect(profile.displayOverrides.isEmpty)
        #expect(profile.layout.visible == [item, foreign])
    }

    @Test("Stale or disconnected displays cannot be captured")
    func unavailable() {
        let profile = BarlineProfile(name: "Example")
        #expect(throws: DisplayVariantCapture.Failure.self) {
            try DisplayVariantCapture.capture(profile: profile, snapshot: snapshot(age: 6), displayID: display, now: now)
        }
        #expect(throws: DisplayVariantCapture.Failure.self) {
            try DisplayVariantCapture.capture(profile: profile, snapshot: snapshot(), displayID: MenuBarDisplayID("missing"), now: now)
        }
    }

    @Test("Ambiguous hardware cannot create an unsafe reconnect mapping")
    func ambiguous() {
        let fingerprint = MenuBarDisplayHardwareFingerprint("v1:" + String(repeating: "a", count: 64))
        #expect(throws: DisplayVariantCapture.Failure.self) {
            try DisplayVariantCapture.capture(profile: BarlineProfile(name: "Example"), snapshot: snapshot(identities: [
                MenuBarDisplayIdentity(runtimeID: display, hardwareFingerprint: fingerprint),
                MenuBarDisplayIdentity(runtimeID: other, hardwareFingerprint: fingerprint),
            ]), displayID: display, now: now)
        }
    }
}
