//
//  MenuBarSectionAvailabilityPolicyTests.swift
//  Barline
//

@testable import BarlineCore
import Testing

@Suite("Menu-bar section availability")
struct MenuBarSectionAvailabilityPolicyTests {
    @Test("The primary section survives transient AppKit visibility loss")
    func primarySectionRemainsEnabled() {
        #expect(
            MenuBarSectionAvailabilityPolicy.isEnabled(
                isPrimarySection: true,
                controlItemIsAdded: false
            )
        )
    }

    @Test("Divider sections require an installed control item")
    func dividerSectionsFollowControlItemAvailability() {
        #expect(
            !MenuBarSectionAvailabilityPolicy.isEnabled(
                isPrimarySection: false,
                controlItemIsAdded: false
            )
        )
        #expect(
            MenuBarSectionAvailabilityPolicy.isEnabled(
                isPrimarySection: false,
                controlItemIsAdded: true
            )
        )
    }
}
