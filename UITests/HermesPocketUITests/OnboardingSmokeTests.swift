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
        let address = app.textFields["Server Address"]
        let username = app.textFields["Username"]
        let password = app.secureTextFields["Password"]
        let signIn = app.buttons["Sign In"]

        XCTAssertTrue(username.waitForExistence(timeout: 10))
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertFalse(signIn.isEnabled)
        attachScreenshot(app, name: "Onboarding-Light-Initial")

        address.tap()
        address.typeText("http://hermes.example.com")
        username.tap()
        username.typeText("smoke-test-user")
        password.tap()
        password.typeText("dummy-not-a-real-password")

        // The production UI validates HTTPS locally before calling the store.
        // An invalid address may disable the button or show this inline error.
        reveal(signIn, in: app)
        if signIn.isEnabled {
            signIn.tap()
            XCTAssertTrue(app.staticTexts[
                "Enter a valid HTTPS server address without credentials or query parameters."
            ].waitForExistence(timeout: 10))
        }
        XCTAssertFalse(app.staticTexts["Connecting…"].exists)

        reveal(address, in: app, direction: .down)
        address.tap()
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "http://hermes.example.com".count))
        address.typeText("https://hermes.example.com")
        reveal(signIn, in: app)
        XCTAssertTrue(signIn.isEnabled)
        // Deliberately do not submit a valid endpoint: no backend or real account
        // is part of this onboarding smoke test.

        let advanced = app.buttons["Advanced Connection"]
        reveal(advanced, in: app)
        XCTAssertTrue(advanced.waitForExistence(timeout: 10))
        advanced.tap()
        let useToken = app.switches["Use an Access Token"]
        reveal(useToken, in: app)
        XCTAssertTrue(useToken.waitForExistence(timeout: 10))
        useToken.tap()
        XCTAssertTrue(app.secureTextFields["Access Token"].waitForExistence(timeout: 10))
        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertFalse(connect.isEnabled)
        attachScreenshot(app, name: "Onboarding-Light-Access-Token")
    }

    func testDarkOnboardingScreenshot() {
        let app = launchOnboarding(style: "Dark")
        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Onboarding-Requested-Dark")
    }

    func testLargestDynamicTypeOnboardingScreenshot() {
        let app = launchOnboarding(style: "Light", largestDynamicType: true)
        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Onboarding-Requested-Accessibility-XXXL-Top")
        let signIn = app.buttons["Sign In"]
        reveal(signIn, in: app)
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertTrue(signIn.isHittable, "The action must remain reachable at the requested largest text size.")
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
        XCTAssertTrue(app.textFields["Server Address"].waitForExistence(timeout: 10),
                      "Expected fresh-install onboarding; use an isolated simulator without saved Hermes credentials.")
        return app
    }

    private enum ScrollDirection { case up, down }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, direction: ScrollDirection = .up) {
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<6 {
            if element.isHittable { return }
            // Swipe inside the form, above the keyboard, when it is present.
            let startY: CGFloat = direction == .up ? 0.45 : 0.20
            let endY: CGFloat = direction == .up ? 0.20 : 0.45
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
        }
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
