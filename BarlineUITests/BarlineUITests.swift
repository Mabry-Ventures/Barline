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

    /// Fixture qualification only. The installed-candidate journey shell gate is
    /// separate: this test must never be reported as proof of Barline activation.
    @MainActor
    func testNativeFixtureReportsTargetActionAndClosure() throws {
        try exerciseFixtureTarget("BF Native", rightClick: false)
    }

    @MainActor
    func testPopoverFixtureReportsTargetActionAndClosure() throws {
        try exerciseFixtureTarget("BF Popover", rightClick: false)
    }

    @MainActor
    func testFixtureReportsRightClickIndependently() throws {
        try exerciseFixtureTarget("BF Native", rightClick: true)
    }

    @MainActor
    private func exerciseFixtureTarget(_ target: String, rightClick: Bool) throws {
        let session = UUID().uuidString
        let receiptURL = FileManager.default.temporaryDirectory.appendingPathComponent("barline-fixture-\(session).json")
        defer { try? FileManager.default.removeItem(at: receiptURL) }
        let app = XCUIApplication()
        app.launchEnvironment["BARLINE_FIXTURE_MODE"] = "journey"
        app.launchEnvironment["BARLINE_FIXTURE_SESSION"] = session
        app.launchEnvironment["BARLINE_FIXTURE_RECEIPT"] = receiptURL.path
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }
        let item = app.menuBars.menuBarItems[target]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The actual fixture status item must be reachable")
        if rightClick {
            item.rightClick()
        } else {
            item.click()
        }
        let action = target == "BF Popover" && !rightClick
            ? app.buttons["fixture-journey-action"] : app.menuItems["Fixture Receipt Action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.click()
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            return receipt["session"] as? String == session &&
                receipt["button"] as? String == (rightClick ? "right" : "left") &&
                receipt["actions"] as? Int == 1 &&
                receipt["opens"] as? Int == 1 &&
                receipt["closes"] as? Int == 1 &&
                receipt["visible"] as? Bool == false
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 5), .completed)
    }
}
