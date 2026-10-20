import XCTest

// P04-00 — the three living screens (Bugün, Ben, Yolum) on Simulator and device: first minute without
// any stored data, the court's stones, the real Life Path on stone 1, session-only choices, the evidence
// ladder, the accessibility audit, Dynamic Type at an accessibility size. Screenshots are attached
// (kept always) and exported as the "after" evidence. Launch argument "-uitest-reset" starts clean.
final class LivingExperienceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
    }

    private func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func waitTap(_ id: String, timeout: TimeInterval = 15) {
        let e = element(id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(id)")
        _ = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: e)], timeout: 5)
        e.tap()
    }
    private func scrollTo(_ id: String) { let e = element(id); for _ in 0..<8 where !(e.exists && e.isHittable) { app.swipeUp() } }
    private func scrollTop() { for _ in 0..<6 { app.swipeDown() } }
    private func typeDate(_ y: String, _ m: String, _ d: String) {
        let yf = app.textFields["date.year"], mf = app.textFields["date.month"], df = app.textFields["date.day"]
        XCTAssertTrue(yf.waitForExistence(timeout: 5))
        yf.tap(); yf.typeText(y); mf.tap(); mf.typeText(m); df.tap(); df.typeText(d)
    }
    private func skipOnboarding() { app.launch(); waitTap("onboarding.skip"); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5)) }
    private func tab(_ i: Int) { app.tabBars.buttons.element(boundBy: i).tap() }

    /// Tab roots: every audit type except .contrast (floating glass tab bar; KNOWN_LIMITATION P03-02, contrast is
    /// measured by ContrastTests and the court's own pairs by CourtContrastTests). Pushed screens: the same set.
    private func audit(_ screen: String) throws {
        _ = XCTWaiter().wait(for: [expectation(description: "settle")], timeout: 1.2)
        let collector = IssueSink()
        try app.performAccessibilityAudit(for: [.dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait]) { issue in
            collector.add("\(screen): \(issue.auditType) — \(issue.compactDescription) — \(issue.element?.description ?? "")"); return true
        }
        let issues = collector.all
        let a = XCTAttachment(string: issues.isEmpty ? "no findings" : issues.joined(separator: "\n")); a.name = "a11y-audit-\(screen)"; a.lifetime = .keepAlways; add(a)
        XCTAssertTrue(issues.isEmpty, "a11y audit findings on \(screen):\n" + issues.joined(separator: "\n"))
    }

    /// A. First minute: no stored data → one discovery (worked example), one invitation, the court; fill
    /// stone 1 from Bugün; the discovery becomes the person's own exact result; choose an intention.
    func testBugunFirstMinute() throws {
        skipOnboarding()
        XCTAssertTrue(element("today.empty").waitForExistence(timeout: 5), "discovery card in its empty form")
        XCTAssertTrue(element("badge.systemInvitation").exists, "the invitation is labelled as the system's")
        XCTAssertTrue(element("map.station.1").waitForExistence(timeout: 5), "the court is on the home screen")
        shot("A1-bugun-ilk-dakika")
        try audit("bugun-empty")
        waitTap("today.fillOrigin")
        XCTAssertTrue(element("station.panel.1").waitForExistence(timeout: 5))
        shot("A2-koken-tasi-bos")
        typeDate("1998", "6", "30")
        waitTap("lifepath.compute")
        XCTAssertTrue(app.staticTexts["lifepath.root"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lifepath.root"].label, "Kök sayı 9", "BOOT-01 engine result unchanged")
        XCTAssertTrue(app.staticTexts["lifepath.trace"].exists, "the full trace is one level down, not hidden")
        shot("A3-koken-tasi-dolu")
        try audit("koken-panel")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("today.discovery").waitForExistence(timeout: 5), "discovery now comes from the person's own trace")
        XCTAssertEqual(app.staticTexts["lifepath.root"].label, "Kök sayı 9")
        XCTAssertTrue(element("badge.exactMath").exists, "the discovery is labelled exact math")
        shot("A4-bugun-canli")
        waitTap("today.chooseIntention")
        waitTap("intention.step.0")
        XCTAssertEqual(element("intention.step.0").value as? String, "seçili")
        shot("A5-niyet-secildi")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("today.changeIntention").waitForExistence(timeout: 5), "the chosen intention shows on Bugün as the person's report")
        try audit("bugun-living")
        shot("A6-bugun-niyetli")
    }

    /// B. Ben: the court, the inline panel per stone, the real feature on stone 1, planned stones say their phase.
    func testBenPersonalMap() throws {
        skipOnboarding()
        tab(1)
        XCTAssertTrue(element("map.station.0").waitForExistence(timeout: 5))
        shot("B1-ben-harita-bos")
        try audit("ben-empty")
        scrollTo("station.panel.1")
        XCTAssertTrue(element("station.panel.1").exists, "stone 1 is selected by default")
        scrollTo("lifepath.compute")
        typeDate("1998", "6", "30")
        waitTap("lifepath.compute")
        XCTAssertTrue(app.staticTexts["lifepath.trace"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lifepath.root"].label, "Kök sayı 9")
        scrollTop()
        shot("B2-ben-koken-etkin")
        waitTap("map.station.7")
        XCTAssertTrue(element("station.panel.7").waitForExistence(timeout: 5), "a planned stone opens its panel")
        scrollTo("station.panel.7")
        XCTAssertTrue(element("badge.notBuilt").exists, "a planned stone is labelled not built")
        scrollTop()
        shot("B3-ben-planli-tas")
        waitTap("map.station.0")
        XCTAssertTrue(element("station.panel.0").waitForExistence(timeout: 5))
        scrollTo("station.contract.toggle")
        waitTap("station.contract.toggle")
        shot("B4-ben-sozlesme")
        try audit("ben-contract")
        scrollTo("self.security")
        waitTap("self.security")
        XCTAssertTrue(element("security.selftest").waitForExistence(timeout: 5), "the security surface is one level down, unchanged")
        shot("B5-guvenlik")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("map.station.0").waitForExistence(timeout: 5))
    }

    /// C. Yolum: a labelled synthetic scenario, one weekly step, the honest P0 → P1 ladder, the step reaches Bugün.
    func testYolumFutureSelfPreview() throws {
        skipOnboarding()
        tab(3)
        XCTAssertTrue(element("path.scenario").waitForExistence(timeout: 5))
        XCTAssertTrue(element("evidence.noStep").exists, "no evidence before a direction")
        shot("C1-yolum-senaryo")
        try audit("yolum-empty")
        waitTap("path.step.1")
        XCTAssertTrue(element("evidence.tier.0").waitForExistence(timeout: 5))
        XCTAssertEqual(element("evidence.tier.0").value as? String, "ulaşıldı", "P0 planned as soon as a step is chosen")
        XCTAssertEqual(element("evidence.tier.1").value as? String, "ulaşılmadı")
        shot("C2-yolum-adim-secildi")
        scrollTo("evidence.didIt")
        waitTap("evidence.didIt")
        XCTAssertEqual(element("evidence.tier.1").value as? String, "ulaşıldı", "P1 is a self-report")
        XCTAssertEqual(element("evidence.tier.2").value as? String, "ulaşılmadı", "P2 is unreachable in this build")
        shot("C3-yolum-p1")
        try audit("yolum-p1")
        tab(0)
        XCTAssertTrue(element("today.weekStep").waitForExistence(timeout: 5), "the weekly step reaches Bugün (connector 9→0 live)")
        shot("C4-bugun-haftalik-adim")
        tab(1)
        waitTap("map.station.10")
        XCTAssertTrue(element("station.panel.10").waitForExistence(timeout: 5))
        XCTAssertTrue(element("evidence.tier.1").exists)
        shot("C5-ben-kanit-tasi")
    }

    /// Dynamic Type at an accessibility size: the three screens still pass the audit and nothing is clipped.
    func testAccessibilitySizeAudit() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        skipOnboarding()
        shot("D1-bugun-accessibilityL")
        try audit("bugun-accessibilityL")
        tab(1)
        XCTAssertTrue(element("map.station.0").waitForExistence(timeout: 5))
        shot("D2-ben-accessibilityL")
        try audit("ben-accessibilityL")
        tab(3)
        XCTAssertTrue(element("path.scenario").waitForExistence(timeout: 5))
        shot("D3-yolum-accessibilityL")
        try audit("yolum-accessibilityL")
    }
}

private final class IssueSink: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
