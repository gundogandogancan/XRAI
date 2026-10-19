import XCTest

// P03-01 §6 + P03-02 G4/G5 UI flows on Simulator and device. Screenshots are attached to the xcresult.
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

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    /// Waits until the element exists AND is hittable, then taps exactly once (unique ids per step).
    private func waitTap(_ id: String, timeout: TimeInterval = 15) {
        let e = element(id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(id)")
        _ = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: e)], timeout: 5)
        e.tap()
    }

    /// An empty SwiftUI TextField reports its placeholder as `value` on the Simulator and "" on a device.
    private static func isEmptyField(_ f: XCUIElement) -> Bool {
        let v = (f.value as? String) ?? ""
        return v.isEmpty || v == "Yıl" || v == "Ay" || v == "Gün" || v == f.placeholderValue
    }

    private func typeDate(_ y: String, _ m: String, _ d: String) {
        let yf = app.textFields["date.year"], mf = app.textFields["date.month"], df = app.textFields["date.day"]
        XCTAssertTrue(yf.waitForExistence(timeout: 5))
        yf.tap(); yf.typeText(y); mf.tap(); mf.typeText(m); df.tap(); df.typeText(d)
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
        typeDate("1998", "6", "30")
        waitTap("onboarding.compute")
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lifepath.root"].label, "Kök sayı 9")
        shot("05-preview")
        waitTap("onboarding.finish")
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5), "Bugün shows the session Life Path")
        XCTAssertTrue(element("badge.systemInvitation").waitForExistence(timeout: 5), "G3: the invitation is labelled as the system's, not the user's")
        shot("06-today-with-lifepath")
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["lifepath.trace"].waitForExistence(timeout: 5))
        shot("07-ben-trace")
    }

    func testSkipFromWelcome() {
        app.launch()
        waitTap("onboarding.skip")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element("today.empty").waitForExistence(timeout: 5))
        shot("08-skipped-today-empty")
        for i in 0..<5 { app.tabBars.buttons.element(boundBy: i).tap(); shot("09-tab-\(i)") }
    }

    func testInvalidDateShowsProblemAndDoesNotAdvance() {
        app.launch()
        waitTap("onboarding.start"); waitTap("onboarding.next.whatItDoes"); waitTap("onboarding.next.privacy")
        typeDate("1900", "2", "29")
        waitTap("onboarding.compute")
        XCTAssertTrue(app.staticTexts["date.problem"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["lifepath.root"].exists)
        shot("10-invalid-date")
        waitTap("onboarding.continueWithoutDate")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        // G1: the unconfirmed text did not survive — Ben shows empty fields
        app.tabBars.buttons.element(boundBy: 1).tap()
        let y = app.textFields["date.year"]
        XCTAssertTrue(y.waitForExistence(timeout: 5))
        XCTAssertTrue(Self.isEmptyField(y), "draft year must be empty (placeholder or empty value)")
    }

    func testBackgroundAndForegroundKeepsSession() {
        app.launch()
        waitTap("onboarding.start"); waitTap("onboarding.next.whatItDoes"); waitTap("onboarding.next.privacy")
        typeDate("2000", "2", "29")
        waitTap("onboarding.compute"); waitTap("onboarding.finish")
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5), "in-memory session survives background within one process")
        shot("11-after-foreground")
        app.launchArguments = []
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "onboarding not repeated")
        XCTAssertFalse(app.staticTexts["lifepath.root"].exists, "date gone after relaunch")
        shot("12-after-relaunch")
    }

    func testForgetClearsDateAndDraftInBen() {
        app.launch()
        waitTap("onboarding.start"); waitTap("onboarding.next.whatItDoes"); waitTap("onboarding.next.privacy")
        typeDate("1998", "6", "30")
        waitTap("onboarding.compute"); waitTap("onboarding.finish")
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["lifepath.trace"].waitForExistence(timeout: 5))
        waitTap("lifepath.forget")
        XCTAssertFalse(app.staticTexts["lifepath.root"].exists, "G1: date gone after forget")
        let y = app.textFields["date.year"]
        XCTAssertTrue(y.waitForExistence(timeout: 5))
        XCTAssertTrue(Self.isEmptyField(y), "G1: draft cleared too")
        shot("15-after-forget")
        typeDate("1955", "1", "1")
        waitTap("lifepath.compute")
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lifepath.root"].label, "Kök sayı 22")
        app.tabBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5), "Bugün reflects the new date")
    }

    func testDynamicTypeLargeSkipIsVisibleAndLastCardReachable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        let skip = element("onboarding.skip")
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        XCTAssertTrue(skip.isHittable, "F-UX-1: skip must be visible without scrolling at AccessibilityL")
        shot("13-welcome-accessibilityL")
        skip.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 1).tap()
        let last = element("prefs.resetOnboarding")
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        for _ in 0..<8 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable, "F-UX-2: last card hidden under the tab bar")
        shot("14-ben-accessibilityL-bottom")
    }

    func testAccessibilityAuditOnKeyScreens() throws {
        app.launch()
        try auditIfSupported("welcome")
        waitTap("onboarding.start"); waitTap("onboarding.next.whatItDoes"); waitTap("onboarding.next.privacy")
        try auditIfSupported("birthdate")
        typeDate("1998", "6", "30")
        waitTap("onboarding.compute")
        try auditIfSupported("preview")
        waitTap("onboarding.finish")
        // Tab screens: every audit type except .contrast. KNOWN_LIMITATION (documented in the
        // P03-02 report): iOS 26's translucent floating tab bar lets scrolled content show through,
        // and the audit measures that blended region as a contrast failure even though the same
        // text is AA-compliant in its own card (token pairs are measured by ContrastTests). A hard
        // scroll edge did not change the audit result. The colours themselves are not the problem.
        try auditIfSupported("today", excludingContrast: true)
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["lifepath.trace"].waitForExistence(timeout: 5))
        try auditIfSupported("ben", excludingContrast: true)
    }

    /// XCUI automated accessibility audit (iOS 17+). Every issue is attached with the screen name and
    /// counted; the test fails if any issue remains (so findings are never silently accepted).
    private func auditIfSupported(_ screen: String, excludingContrast: Bool = false) throws {
        // Let step transitions and keyboard dismissal settle so the audit samples the final frame,
        // not a mid-animation opacity.
        _ = XCTWaiter().wait(for: [expectation(description: "settle")], timeout: 1.2)
        let collector = IssueCollector()
        let types: XCUIAccessibilityAuditType = excludingContrast
            ? [.dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait]
            : .all
        try app.performAccessibilityAudit(for: types) { issue in
            collector.add("\(screen): \(issue.auditType) — \(issue.compactDescription) — \(issue.element?.description ?? "")")
            return true   // handled here (collected), audit continues
        }
        let issues = collector.all
        let a = XCTAttachment(string: issues.isEmpty ? "\(screen): no issues" : issues.joined(separator: "\n"))
        a.name = "a11y-audit-\(screen)"; a.lifetime = .keepAlways
        add(a)
        XCTAssertTrue(issues.isEmpty, "a11y audit findings on \(screen):\n" + issues.joined(separator: "\n"))
    }
}

/// Thread-safe sink for audit findings (Swift 6 strict concurrency: the audit closure is Sendable).
private final class IssueCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
