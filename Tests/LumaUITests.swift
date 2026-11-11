import XCTest
final class LumaUITests:XCTestCase {
    func launch(reset:Bool=true)->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--ui-testing"]+(reset ? ["--reset-ui-testing"] : []);app.launch();return app
    }
    func onboard(_ app:XCUIApplication) {
        let button=app.buttons["Start my sleep diary"]
        if !button.isHittable{app.swipeUp()}
        XCTAssertTrue(button.waitForExistence(timeout:5));button.tap()
    }
    func testManualEntryReachesHistory() {
        let app=launch();onboard(app);app.tabBars.buttons["Track"].tap();app.buttons["Add sleep"].tap();app.navigationBars.buttons["Save"].tap();app.tabBars.buttons["History"].tap();XCTAssertTrue(app.staticTexts["Every night tells a story."].exists)
    }
    func testTimerSurvivesRelaunch() {
        var app=launch();onboard(app);app.tabBars.buttons["Track"].tap();app.buttons["Start bedtime"].tap();app.terminate()
        app=launch(reset:false);app.tabBars.buttons["Track"].tap();XCTAssertTrue(app.buttons["I'm awake"].exists)
    }
    func testDemoLabel() {
        let app=launch();app.swipeUp();app.buttons["Explore a clearly labeled demo"].tap();XCTAssertTrue(app.staticTexts["DEMO · sample history"].waitForExistence(timeout:5))
    }
}
