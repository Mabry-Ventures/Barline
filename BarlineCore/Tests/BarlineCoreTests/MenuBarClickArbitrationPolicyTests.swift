//
//  MenuBarClickArbitrationPolicyTests.swift
//  Barline
//

@testable import BarlineCore
import Testing

@Suite("Menu-bar click arbitration")
struct MenuBarClickArbitrationPolicyTests {
    @Test("Target-action ownership wins even if every geometry cache describes a gap")
    func primaryWindowOwnsClickDespiteStaleGeometry() {
        #expect(
            !MenuBarClickArbitrationPolicy.isEmptyMenuBarSpace(
                isInsideMenuBar: true,
                isInsideApplicationMenu: false,
                isInsidePrimaryControlItem: false,
                isInsideCachedMenuBarItem: false,
                isInsideNotch: false,
                eventTargetsPrimaryControlItem: true
            )
        )
    }

    @Test("A cold cache cannot classify the primary control item as empty space")
    func primaryControlItemWinsOverColdCache() {
        #expect(
            !MenuBarClickArbitrationPolicy.isEmptyMenuBarSpace(
                isInsideMenuBar: true,
                isInsideApplicationMenu: false,
                isInsidePrimaryControlItem: true,
                isInsideCachedMenuBarItem: false,
                isInsideNotch: false
            )
        )
    }

    @Test("A genuine menu-bar gap remains eligible for global click handling")
    func genuineEmptySpace() {
        #expect(
            MenuBarClickArbitrationPolicy.isEmptyMenuBarSpace(
                isInsideMenuBar: true,
                isInsideApplicationMenu: false,
                isInsidePrimaryControlItem: false,
                isInsideCachedMenuBarItem: false,
                isInsideNotch: false
            )
        )
    }

    @Test("Known occupied menu-bar regions are never empty")
    func occupiedRegions() {
        #expect(
            !MenuBarClickArbitrationPolicy.isEmptyMenuBarSpace(
                isInsideMenuBar: true,
                isInsideApplicationMenu: true,
                isInsidePrimaryControlItem: false,
                isInsideCachedMenuBarItem: false,
                isInsideNotch: false
            )
        )
        #expect(
            !MenuBarClickArbitrationPolicy.isEmptyMenuBarSpace(
                isInsideMenuBar: true,
                isInsideApplicationMenu: false,
                isInsidePrimaryControlItem: false,
                isInsideCachedMenuBarItem: true,
                isInsideNotch: false
            )
        )
        #expect(
            !MenuBarClickArbitrationPolicy.isEmptyMenuBarSpace(
                isInsideMenuBar: true,
                isInsideApplicationMenu: false,
                isInsidePrimaryControlItem: false,
                isInsideCachedMenuBarItem: false,
                isInsideNotch: true
            )
        )
    }
}
