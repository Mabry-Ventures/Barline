@testable import BarlineCore
import Testing

@Suite("Physical menu-bar click visibility")
struct MenuBarVisibilityPolicyTests {
    private let primary = MenuBarRect(x: 0, y: 0, width: 1728, height: 1117)
    private let normal = MenuBarRect(x: 800, y: 0, width: 90, height: 33)

    @Test("A hosted item outside every display is not clickable despite its visible flag")
    func capturedOffscreenHostedItem() {
        #expect(!MenuBarVisibilityPolicy.isClickable(
            reportedVisible: true,
            itemBounds: MenuBarRect(x: -4283, y: 0, width: 90, height: 33),
            displayBounds: [primary]
        ))
    }

    @Test("Both the reported flag and a physical display are required")
    func normalVisibility() {
        #expect(MenuBarVisibilityPolicy.isClickable(reportedVisible: true, itemBounds: normal, displayBounds: [primary]))
        #expect(!MenuBarVisibilityPolicy.isClickable(reportedVisible: false, itemBounds: normal, displayBounds: [primary]))
        #expect(!MenuBarVisibilityPolicy.isClickable(reportedVisible: true, itemBounds: normal, displayBounds: []))
    }

    @Test("Real displays to the left or above the primary support negative coordinates")
    func negativeCoordinateDisplays() {
        let left = MenuBarRect(x: -1728, y: 0, width: 1728, height: 1117)
        let above = MenuBarRect(x: 0, y: -1117, width: 1728, height: 1117)
        #expect(MenuBarVisibilityPolicy.isClickable(
            reportedVisible: true,
            itemBounds: MenuBarRect(x: -1600, y: 0, width: 90, height: 33),
            displayBounds: [primary, left]
        ))
        #expect(MenuBarVisibilityPolicy.isClickable(
            reportedVisible: true,
            itemBounds: MenuBarRect(x: 800, y: -1117, width: 90, height: 33),
            displayBounds: [primary, above]
        ))
    }

    @Test("The union bounding box cannot make a gap between monitors clickable")
    func gapBetweenDisplays() {
        #expect(!MenuBarVisibilityPolicy.isClickable(
            reportedVisible: true,
            itemBounds: MenuBarRect(x: 1800, y: 0, width: 90, height: 33),
            displayBounds: [primary, MenuBarRect(x: 2000, y: 0, width: 1728, height: 1117)]
        ))
    }

    @Test("A clipped item's click center, not any intersecting edge, determines visibility")
    func partiallyClipped() {
        #expect(!MenuBarVisibilityPolicy.isClickable(
            reportedVisible: true,
            itemBounds: MenuBarRect(x: -60, y: 0, width: 90, height: 33),
            displayBounds: [primary]
        ))
        #expect(MenuBarVisibilityPolicy.isClickable(
            reportedVisible: true,
            itemBounds: MenuBarRect(x: -40, y: 0, width: 90, height: 33),
            displayBounds: [primary]
        ))
        #expect(!MenuBarVisibilityPolicy.isClickable(
            reportedVisible: true,
            itemBounds: MenuBarRect(x: 1683, y: 0, width: 90, height: 33),
            displayBounds: [primary]
        ))
    }

    @Test("Malformed item geometry fails closed", arguments: invalidBounds)
    func invalidItemBounds(_ rect: MenuBarRect) {
        #expect(!MenuBarVisibilityPolicy.isClickable(reportedVisible: true, itemBounds: rect, displayBounds: [primary]))
    }

    @Test("Malformed display geometry fails closed", arguments: invalidBounds)
    func invalidDisplayBounds(_ rect: MenuBarRect) {
        #expect(!MenuBarVisibilityPolicy.isClickable(reportedVisible: true, itemBounds: normal, displayBounds: [rect]))
    }

    @Test("An invalid display does not invalidate another real display")
    func validDisplaySurvivesMalformedSibling() {
        #expect(MenuBarVisibilityPolicy.isClickable(
            reportedVisible: true,
            itemBounds: normal,
            displayBounds: [MenuBarRect(x: 0, y: 0, width: .infinity, height: 1117), primary]
        ))
    }

    private static let invalidBounds: [MenuBarRect] = [
        .zero,
        MenuBarRect(x: 0, y: 0, width: 0, height: 33),
        MenuBarRect(x: 0, y: 0, width: 90, height: 0),
        MenuBarRect(x: 0, y: 0, width: -90, height: 33),
        MenuBarRect(x: 0, y: 0, width: 90, height: -33),
        MenuBarRect(x: .nan, y: 0, width: 90, height: 33),
        MenuBarRect(x: 0, y: .nan, width: 90, height: 33),
        MenuBarRect(x: 0, y: 0, width: .nan, height: 33),
        MenuBarRect(x: 0, y: 0, width: 90, height: .nan),
        MenuBarRect(x: .infinity, y: 0, width: 90, height: 33),
        MenuBarRect(x: 0, y: -.infinity, width: 90, height: 33),
        MenuBarRect(x: 0, y: 0, width: .infinity, height: 33),
        MenuBarRect(x: 0, y: 0, width: 90, height: .infinity),
        MenuBarRect(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 33),
        MenuBarRect(x: 0, y: .greatestFiniteMagnitude, width: 90, height: .greatestFiniteMagnitude),
    ]
}
