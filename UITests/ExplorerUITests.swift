import XCTest

@MainActor
final class ExplorerUITests: XCTestCase {
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        return app
    }

    func testLaunchToRocketNavigation() {
        let app = launchDemo()
        let mission = app.buttons["launch-demo-launch-24"]
        XCTAssertTrue(mission.waitForExistence(timeout: 10))
        mission.tap()
        let rocket = app.buttons["rocketCard"]
        if !rocket.isHittable { app.swipeUp() }
        XCTAssertTrue(rocket.waitForExistence(timeout: 5))
        rocket.tap()
        XCTAssertTrue(app.navigationBars["Rocket details"].waitForExistence(timeout: 5))
    }

    func testRocketsPagination() {
        let app = launchDemo()
        app.tabBars.buttons["Rockets"].tap()
        XCTAssertTrue(app.buttons["rocket-demo-falcon1"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["loadMore"].isHittable { app.swipeUp() }
        app.buttons["loadMore"].tap()
        for _ in 0..<4 where !app.buttons["rocket-demo-starship"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["rocket-demo-starship"].exists)
    }

    func testDateFilterCanBeAppliedAndCleared() {
        let app = launchDemo()
        app.buttons["filterDates"].tap()
        XCTAssertTrue(app.navigationBars["Date range"].waitForExistence(timeout: 5))
        app.buttons["applyDateRange"].tap()
        XCTAssertTrue(app.staticTexts["appliedDateRange"].waitForExistence(timeout: 5))
        app.buttons["Clear"].tap()
        XCTAssertFalse(app.staticTexts["appliedDateRange"].exists)
    }
}
