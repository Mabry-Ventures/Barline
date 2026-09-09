import BarlineCore
import XCTest

final class BarlineTests: XCTestCase {
    func testFixtureCanConstructStableMenuBarIdentity() {
        let identity = MenuBarItemID(bundleIdentifier: "com.example.fixture", title: "Fixture")
        XCTAssertTrue(identity.isPlausiblyStable)
        XCTAssertEqual(identity.description, "com.example.fixture|fixture")
    }

    func testDockPreferenceKeepsEveryRequestedPolicyAccessory() {
        XCTAssertFalse(
            DockVisibilityPolicy.usesRegularActivationPolicy(
                requestedRegular: true,
                hideDockIcon: true
            )
        )
        XCTAssertFalse(
            DockVisibilityPolicy.usesRegularActivationPolicy(
                requestedRegular: false,
                hideDockIcon: true
            )
        )
    }

    func testVisibleDockPreservesRequestedPolicy() {
        XCTAssertTrue(
            DockVisibilityPolicy.usesRegularActivationPolicy(
                requestedRegular: true,
                hideDockIcon: false
            )
        )
        XCTAssertFalse(
            DockVisibilityPolicy.usesRegularActivationPolicy(
                requestedRegular: false,
                hideDockIcon: false
            )
        )
    }
}
