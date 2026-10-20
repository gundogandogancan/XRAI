import XCTest

// P03-05A GATE 4/5/6 — consent and restore-risk screens on synthetic state, with the accessibility audit.
final class ConsentUITests: XCTestCase {
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

    private func openConsent() {
        app.launch()
        waitTap("onboarding.skip")
        app.tabBars.buttons.element(boundBy: 1).tap()
        scrollTo("self.consent")
        waitTap("self.consent")
        XCTAssertTrue(element("consent.intro").waitForExistence(timeout: 5))
    }

    func testGrantRevokeAndHistory() throws {
        openConsent()
        shot("20-consent-list")
        waitTap("consent.purpose.journal_reflection")
        XCTAssertTrue(element("consent.qa.0").waitForExistence(timeout: 5))
        for i in 0..<8 { XCTAssertTrue(element("consent.qa.\(i)").exists, "question \(i) shown before any grant") }
        shot("21-purpose-detail")
        scrollTo("consent.action.grant")
        waitTap("consent.action.grant")
        waitTap("consent.confirm.grant")
        XCTAssertTrue(element("consent.action.createRecord").waitForExistence(timeout: 5), "granted: record creation offered")
        shot("22-granted")
        waitTap("consent.action.createRecord")
        scrollTo("consent.action.revokeSuspend")
        waitTap("consent.action.revokeSuspend")
        waitTap("consent.confirm.revokeSuspend")
        XCTAssertTrue(element("consent.action.grant").waitForExistence(timeout: 5), "revoked: grant offered again")
        XCTAssertTrue(element("consent.action.restoreSuspended").waitForExistence(timeout: 5), "suspended records can be restored explicitly")
        shot("23-revoked-suspended")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollTo("consent.history")
        waitTap("consent.history")
        XCTAssertFalse(element("consent.history.empty").waitForExistence(timeout: 2), "two events recorded")
        shot("24-history")
    }

    func testThirdPartyPurposeHasNoSuspension() {
        openConsent()
        waitTap("consent.purpose.symbolic_family_lens")
        scrollTo("consent.action.grant")
        waitTap("consent.action.grant")
        waitTap("consent.confirm.grant")
        XCTAssertTrue(element("consent.action.revokeDeleteNow").waitForExistence(timeout: 5))
        XCTAssertFalse(element("consent.action.revokeSuspend").exists, "third-party data: no suspension option")
        shot("25-third-party")
    }

    func testRestoreRiskExactAcknowledgment() {
        app.launch()
        waitTap("onboarding.skip")
        app.tabBars.buttons.element(boundBy: 1).tap()
        scrollTo("self.restore")
        waitTap("self.restore")
        XCTAssertTrue(element("restore.intro").waitForExistence(timeout: 5))
        shot("26-restore-list")
        let activate = element("restore.activate.r-older")
        scrollTo("restore.activate.r-older")
        XCTAssertTrue(activate.waitForExistence(timeout: 5))
        XCTAssertFalse(activate.isEnabled, "nothing acknowledged → disabled")
        element("restore.ack.r-older.16").switches.firstMatch.tap()
        XCTAssertFalse(activate.isEnabled, "one of two risks → still disabled (exact set)")
        element("restore.ack.r-older.128").switches.firstMatch.tap()
        XCTAssertTrue(activate.isEnabled)
        activate.tap()
        XCTAssertTrue(element("restore.outcome.r-older").waitForExistence(timeout: 5))
        scrollTo("restore.noactivate.r-possibly")
        XCTAssertTrue(element("restore.noactivate.r-possibly").exists && element("restore.reimport.r-possibly").exists, "possibly deleted: no activation, re-import offered")
        XCTAssertFalse(element("restore.activate.r-possibly").exists)
        scrollTo("restore.noreset")
        XCTAssertTrue(element("restore.noreset").exists, "no reset button is shown as if it existed")
        shot("27-restore-risks")
    }

    func testAccessibilityAuditOnConsentScreens() throws {
        openConsent()
        try audit("consent-list")
        waitTap("consent.purpose.journal_reflection")
        XCTAssertTrue(element("consent.qa.0").waitForExistence(timeout: 5))
        try audit("consent-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollTo("self.restore")
        waitTap("self.restore")
        XCTAssertTrue(element("restore.intro").waitForExistence(timeout: 5))
        try audit("restore-risks")
    }

    private func audit(_ screen: String) throws {
        _ = XCTWaiter().wait(for: [expectation(description: "settle")], timeout: 1.2)
        let collector = AuditSink()
        // Pushed screens sit under the same floating tab bar as the tab roots: contrast is measured by ContrastTests (KNOWN_LIMITATION, P03-02).
        try app.performAccessibilityAudit(for: [.dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait]) { issue in
            collector.add("\(screen): \(issue.auditType) — \(issue.compactDescription) — \(issue.element?.description ?? "")"); return true
        }
        let a = XCTAttachment(string: collector.all.isEmpty ? "\(screen): no issues" : collector.all.joined(separator: "\n")); a.name = "a11y-audit-\(screen)"; a.lifetime = .keepAlways; add(a)
        XCTAssertTrue(collector.all.isEmpty, "a11y audit findings on \(screen):\n" + collector.all.joined(separator: "\n"))
    }
}

private final class AuditSink: @unchecked Sendable {
    private let lock = NSLock(); private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
