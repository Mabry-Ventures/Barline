import BarlineCore
import XCTest

final class BarlineTests: XCTestCase {
    func testFixtureCanConstructStableMenuBarIdentity() {
        let identity = MenuBarItemID(bundleIdentifier: "com.example.fixture", title: "Fixture")
        XCTAssertTrue(identity.isPlausiblyStable)
        XCTAssertEqual(identity.description, "com.example.fixture|fixture")
    }
}
