import XCTest

/// Run on a fresh, isolated simulator: saved Keychain credentials intentionally
/// take the production app past onboarding. These tests never store credentials.
@MainActor
final class OnboardingSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLightOnboardingValidationAndAccessTokenOption() {
        let app = launchOnboarding(style: "Light")
        let address = textField("https://hermes.example.com", in: app)
        let username = textField("Username", in: app)
        let password = secureField("Password", in: app)
        let signIn = app.buttons["Sign In"]

        XCTAssertTrue(username.waitForExistence(timeout: 10))
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        reveal(signIn, in: app)
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertFalse(signIn.isEnabled)
        attachScreenshot(app, name: "Onboarding-Light-Initial")

        reveal(address, in: app, direction: .down)
        address.tap()
        address.typeText("http://hermes.example.com")
        reveal(username, in: app)
        username.tap()
        username.typeText("smoke-test-user")
        reveal(password, in: app)
        password.tap()
        password.typeText("dummy-not-a-real-password")

        // The production UI validates HTTPS locally before calling the store.
        // An invalid address may disable the button or show this inline error.
        reveal(signIn, in: app)
        if signIn.isEnabled {
            signIn.tap()
            let validation = app.staticTexts[
                "Enter a valid HTTPS server address without credentials or query parameters."
            ]
            reveal(validation, in: app)
            XCTAssertTrue(validation.waitForExistence(timeout: 10))
        }
        XCTAssertFalse(app.staticTexts["Connecting…"].exists)

        reveal(address, in: app, direction: .down)
        // Tap beyond this short URL's rendered text to put the caret at its end.
        address.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "http://hermes.example.com".count))
        address.typeText("https://hermes.example.com")
        XCTAssertEqual(address.value as? String, "https://hermes.example.com")
        reveal(signIn, in: app)
        XCTAssertTrue(signIn.isEnabled)
        // Deliberately do not submit a valid endpoint: no backend or real account
        // is part of this onboarding smoke test.

        let advanced = app.buttons["Advanced Connection"]
        reveal(advanced, in: app, direction: .down)
        XCTAssertTrue(advanced.waitForExistence(timeout: 10))
        advanced.tap()
        let useToken = app.switches["Use an Access Token"]
        reveal(useToken, in: app)
        XCTAssertTrue(useToken.waitForExistence(timeout: 10))
        useToken.tap()
        let token = secureField("Access Token", in: app)
        reveal(token, in: app)
        XCTAssertTrue(token.waitForExistence(timeout: 10))
        let connect = app.buttons["Connect"]
        reveal(connect, in: app)
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertFalse(connect.isEnabled)
        attachScreenshot(app, name: "Onboarding-Light-Access-Token")
    }

    func testDarkOnboardingScreenshot() {
        let app = launchOnboarding(style: "Dark")
        XCTAssertTrue(textField("Username", in: app).waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Onboarding-Requested-Dark")
    }

    func testLargestDynamicTypeOnboardingScreenshot() {
        let app = launchOnboarding(style: "Light", largestDynamicType: true)
        attachScreenshot(app, name: "Onboarding-Requested-Accessibility-XXXL-Top")
        let username = textField("Username", in: app)
        reveal(username, in: app)
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        XCTAssertTrue(username.isHittable, "The username field must remain reachable at the requested largest text size.")
        let signIn = app.buttons["Sign In"]
        reveal(signIn, in: app)
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertTrue(isVisibleInForm(signIn, in: app), "The action must remain visible after scrolling at the requested largest text size.")
        XCTAssertFalse(signIn.isEnabled)
        attachScreenshot(app, name: "Onboarding-Requested-Accessibility-XXXL-Action")
    }

    private func launchOnboarding(style: String, largestDynamicType: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // Per-process user-default overrides; no simulator or shared device
        // preferences are changed. Inspect attachments to confirm visual traits;
        // screenshots are observations, not assertions of a pixel baseline.
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", style]
        if largestDynamicType {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        attachScreenshot(app, name: "Launch-\(name)")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Launch-Accessibility-Hierarchy-\(name)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(app.navigationBars["hocket"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your Hermes, within reach."].waitForExistence(timeout: 10))
        XCTAssertTrue(textField("https://hermes.example.com", in: app).waitForExistence(timeout: 10),
                      "Expected fresh-install onboarding; use an isolated simulator without saved Hermes credentials.")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Cannot read the saved connection from Keychain")).firstMatch.exists,
                       "The simulator app must have working Keychain access; inspect signing and entitlements.")
        return app
    }

    // Cloud iOS accessibility captures expose these SwiftUI fields by
    // placeholderValue, with no label. In particular the explicit URL prompt
    // replaces 'Server Address' as the text field's accessible placeholder.
    private func textField(_ placeholder: String, in app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "placeholderValue == %@", placeholder)).firstMatch
    }

    private func secureField(_ placeholder: String, in app: XCUIApplication) -> XCUIElement {
        app.secureTextFields.matching(NSPredicate(format: "placeholderValue == %@", placeholder)).firstMatch
    }

    private enum ScrollDirection { case up, down }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, direction: ScrollDirection = .up) {
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        for _ in 0..<16 {
            if element.exists && (element.isHittable || (!element.isEnabled && isVisibleInForm(element, in: app))) { return }
            // Swipe inside the form, above the keyboard, when it is present.
            let startY: CGFloat = direction == .up ? 0.45 : 0.20
            let endY: CGFloat = direction == .up ? 0.20 : 0.45
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: startY))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: endY)))
        }
        XCTFail("Could not scroll the onboarding form to \(element).")
    }

    private func isVisibleInForm(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, !element.frame.isEmpty else { return false }
        let top = app.navigationBars.firstMatch.frame.maxY
        let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
        let viewport = CGRect(x: app.frame.minX, y: top, width: app.frame.width, height: max(0, bottom - top))
        return viewport.contains(element.frame)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
