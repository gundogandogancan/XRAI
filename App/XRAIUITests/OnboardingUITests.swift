import XCTest

// P03-01 §6 UI flows on Simulator and device. Screenshots are attached to the xcresult.
// The app is launched with "-uitest-reset" so onboarding starts fresh each test.

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Waits until the element exists AND is hittable (device transitions can swallow a tap during
    /// animation), then taps exactly once. Every onboarding step has a unique identifier.
    private func waitTap(_ id: String, timeout: TimeInterval = 15) {
        let e = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(id)")
        let hittable = NSPredicate(format: "isHittable == true")
        _ = XCTWaiter().wait(for: [expectation(for: hittable, evaluatedWith: e)], timeout: 5)
        e.tap()
    }

    func testStartThroughAllStepsWithValidDate() {
        app.launch()
        shot("01-welcome")
        waitTap("onboarding.start")
        shot("02-what-it-does")
        waitTap("onboarding.next.whatItDoes")
        shot("03-privacy")
        waitTap("onboarding.next.privacy")
        shot("04-birthdate")
        let y = app.textFields["date.year"], m = app.textFields["date.month"], d = app.textFields["date.day"]
        XCTAssertTrue(y.waitForExistence(timeout: 5))
        y.tap(); y.typeText("1998"); m.tap(); m.typeText("6"); d.tap(); d.typeText("30")
        waitTap("onboarding.compute")
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lifepath.root"].label, "Kök sayı 9")
        shot("05-preview")
        waitTap("onboarding.finish")
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5), "Bugün shows the session Life Path")
        shot("06-today-with-lifepath")
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["lifepath.trace"].waitForExistence(timeout: 5))
        shot("07-ben-trace")
    }

    func testSkipFromWelcome() {
        app.launch()
        waitTap("onboarding.skip")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["today.empty"].firstMatch.waitForExistence(timeout: 5) || app.staticTexts["Henüz bir başlangıç noktası yok"].waitForExistence(timeout: 5))
        shot("08-skipped-today-empty")
        for i in 0..<5 { app.tabBars.buttons.element(boundBy: i).tap(); shot("09-tab-\(i)") }
    }

    func testInvalidDateShowsProblemAndDoesNotAdvance() {
        app.launch()
        waitTap("onboarding.start"); waitTap("onboarding.next.whatItDoes"); waitTap("onboarding.next.privacy")
        let y = app.textFields["date.year"], m = app.textFields["date.month"], d = app.textFields["date.day"]
        XCTAssertTrue(y.waitForExistence(timeout: 5))
        y.tap(); y.typeText("1900"); m.tap(); m.typeText("2"); d.tap(); d.typeText("29")
        waitTap("onboarding.compute")
        XCTAssertTrue(app.staticTexts["date.problem"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["lifepath.root"].exists)
        shot("10-invalid-date")
        waitTap("onboarding.continueWithoutDate")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testBackgroundAndForegroundKeepsSession() {
        app.launch()
        waitTap("onboarding.start"); waitTap("onboarding.next.whatItDoes"); waitTap("onboarding.next.privacy")
        let y = app.textFields["date.year"], m = app.textFields["date.month"], d = app.textFields["date.day"]
        XCTAssertTrue(y.waitForExistence(timeout: 5))
        y.tap(); y.typeText("2000"); m.tap(); m.typeText("2"); d.tap(); d.typeText("29")
        waitTap("onboarding.compute"); waitTap("onboarding.finish")
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5), "in-memory session survives background within one process")
        shot("11-after-foreground")
        // relaunch = new process: no personal persistence, the date is gone; onboarding flag persists
        app.launchArguments = []
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "onboarding not repeated")
        XCTAssertFalse(app.staticTexts["lifepath.root"].exists, "date gone after relaunch")
        shot("12-after-relaunch")
    }

    func testDynamicTypeLargeDoesNotBreakLayout() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding.start").firstMatch.waitForExistence(timeout: 10))
        shot("13-welcome-accessibilityL")
        waitTap("onboarding.skip")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 1).tap()
        shot("14-ben-accessibilityL")
    }
}
