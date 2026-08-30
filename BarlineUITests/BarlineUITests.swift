//
//  BarlineUITests.swift
//  Barline
//

import XCTest

final class BarlineUITests: XCTestCase {
    @MainActor
    func testFixtureExposesDeterministicAccessibilitySurface() {
        let app = XCUIApplication()
        app.launchEnvironment["BARLINE_FIXTURE_MODE"] = "ui-test"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["fixture-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["fixture-mode"].exists)
        XCTAssertTrue(app.buttons["fixture-apply-profile"].exists)
    }
}
