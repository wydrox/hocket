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

        reveal(username, in: app)
        reveal(password, in: app)
        reveal(signIn, in: app)
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertFalse(signIn.isEnabled)
        attachScreenshot(app, name: "Onboarding-Light-Initial")

        reveal(address, in: app, direction: .down)
        address.tap()
        address.typeText("http://hermes.example.com")
        XCTAssertEqual(address.value as? String, "http://hermes.example.com")
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
                "Enter an HTTPS origin without a path, credentials, query, or fragment."
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
        XCTAssertFalse(app.staticTexts["Enter an HTTPS origin without a path, credentials, query, or fragment."].exists,
                       "Correcting the address must clear the previous validation error.")
        // Deliberately do not submit a valid endpoint: no backend or real account
        // is part of this onboarding smoke test.

        let advanced = app.buttons["Advanced Connection"]
        reveal(advanced, in: app, direction: .down)
        XCTAssertTrue(advanced.waitForExistence(timeout: 10))
        advanced.tap()
        let useToken = app.switches["Use an Access Token"]
        reveal(useToken, in: app)
        XCTAssertTrue(useToken.waitForExistence(timeout: 10))
        // SwiftUI exposes both the whole labeled row and its nested switch.
        // Tapping the row's center can hit only its label; use the actual control.
        let toggleControl = useToken.switches.firstMatch
        if toggleControl.exists { toggleControl.tap() }
        else { useToken.tap() }
        XCTAssertEqual(useToken.value as? String, "1", "The access-token switch must be enabled before its field is located.")
        let token = secureField("Access Token", in: app)
        // Removing the username/password rows can move this new row above the
        // current viewport. Start toward the top; reveal also follows its frame.
        reveal(token, in: app, direction: .down)
        XCTAssertTrue(token.waitForExistence(timeout: 10))
        XCTAssertTrue(token.isHittable, "The access-token option must expose an editable secure field.")
        let connect = app.buttons["Connect"]
        reveal(connect, in: app)
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertFalse(connect.isEnabled)
        attachScreenshot(app, name: "Onboarding-Light-Access-Token")
    }

    func testDarkOnboardingScreenshot() {
        let app = launchOnboarding(style: "Dark")
        reveal(textField("Username", in: app), in: app)
        XCTAssertTrue(textField("Username", in: app).waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Onboarding-Requested-Dark")
    }

    func testSetupGuideAndReturnToEnteredAddress() {
        let app = launchOnboarding(style: "Light")
        let address = textField("https://hermes.example.com", in: app)
        address.tap()
        address.typeText("https://hermes.example.com")
        let setup = app.buttons["Set Up Hermes"]
        reveal(setup, in: app, direction: .down)
        setup.tap()
        XCTAssertTrue(app.navigationBars["Set Up Hermes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Prepare Hermes"].exists)
        attachScreenshot(app, name: "Setup-Prepare-Hermes")

        let desktopHelp = app.buttons["Where to Click in Hermes"]
        reveal(desktopHelp, in: app)
        desktopHelp.tap()
        let actualPath = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Settings → Web access")).firstMatch
        reveal(actualPath, in: app)
        XCTAssertTrue(actualPath.exists)
        attachScreenshot(app, name: "Setup-Hermes-Desktop-Steps")
        reveal(desktopHelp, in: app, direction: .down)
        desktopHelp.tap()

        let next = app.buttons["setup.continue"]
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.staticTexts["Connect Your Device"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Setup-Connect-Device")
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.staticTexts["Sign In to Hermes"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Setup-Sign-In")
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.navigationBars["hocket"].waitForExistence(timeout: 10))
        reveal(address, in: app, direction: .down)
        XCTAssertEqual(address.value as? String, "https://hermes.example.com", "Reading setup help must preserve the entered server address.")
        // The guide and validation checks do not contact this dummy address.
    }

    func testLargestDynamicTypeSetupGuideCanContinueAndClose() {
        let app = launchOnboarding(style: "Dark", largestDynamicType: true)
        let setup = app.buttons["Set Up Hermes"]
        reveal(setup, in: app, direction: .down)
        setup.tap()
        XCTAssertTrue(app.navigationBars["Set Up Hermes"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Setup-Dark-Accessibility-XXXL")
        let next = app.buttons["setup.continue"]
        reveal(next, in: app)
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.staticTexts["Connect Your Device"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["hocket"].waitForExistence(timeout: 10))
    }

    func testLargestDynamicTypeOnboardingScreenshot() {
        let app = launchOnboarding(style: "Light", largestDynamicType: true)
        let address = textField("https://hermes.example.com", in: app)
        XCTAssertTrue(address.isHittable, "The server address must remain reachable at the requested largest text size.")
        attachScreenshot(app, name: "Onboarding-Requested-Accessibility-XXXL-Address")
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
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-hocket-test-appearance", style]
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
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Cannot read the saved connection from Keychain")).firstMatch.exists,
                       "The simulator app must have working Keychain access; inspect signing and entitlements.")
        // Form realizes rows lazily. At accessibility XXXL the introductory
        // text fills the first viewport, so waiting cannot create the URL row.
        reveal(textField("https://hermes.example.com", in: app), in: app)
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

    private enum ScrollDirection: String { case up, down }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        direction: ScrollDirection = .up,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let form = activeForm(in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 10), file: file, line: line)
        var nextDirection = direction
        var previousContent: String?
        var reversedAtBoundary = false
        var trace: [String] = []

        // Eight substantial, viewport-relative drags cover the onboarding form.
        // A stationary viewport reverses the search once, then fails with the
        // actual hierarchy instead of repeating ineffective swipes indefinitely.
        for attempt in 0...8 {
            let viewport = formViewport(in: app)
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            if exists && viewport.contains(frame) && !frame.isEmpty
                && (!element.isEnabled || element.isHittable) { return }

            let content = form.staticTexts.allElementsBoundByIndex.compactMap { text -> String? in
                let bounds = text.frame
                guard viewport.intersects(bounds) else { return nil }
                return "\(text.label)@\(Int(bounds.minY.rounded()))"
            }.joined(separator: " | ")
            trace.append("\(attempt): \(nextDirection.rawValue), target=\(frame), viewport=\(viewport), visible=\(content)")
            guard attempt < 8, viewport.height > 80 else { break }

            if content == previousContent {
                guard !reversedAtBoundary else { break }
                nextDirection = nextDirection == .up ? .down : .up
                reversedAtBoundary = true
            } else if exists && !frame.isEmpty {
                if frame.minY < viewport.minY { nextDirection = .down }
                else if frame.maxY > viewport.maxY { nextDirection = .up }
            }
            previousContent = content

            // CollectionView can include system side areas. Use the center of
            // visible form content and keep both endpoints above the keyboard.
            let x = viewport.midX
            let upperY = viewport.minY + viewport.height * 0.2
            let lowerY = viewport.minY + viewport.height * 0.8
            var distance = lowerY - upperY
            if exists && !frame.isEmpty {
                let needed = nextDirection == .up ? frame.maxY - viewport.maxY : viewport.minY - frame.minY
                if needed > 0 { distance = min(distance, max(40, needed + 24)) }
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: x, dy: nextDirection == .up ? lowerY : upperY))
            let end = origin.withOffset(CGVector(dx: x, dy: nextDirection == .up ? lowerY - distance : upperY + distance))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        attachScreenshot(app, name: "Unreachable-Onboarding-Control")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Unreachable-Onboarding-Control-Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("Could not reveal \(element). Scroll trace:\n\(trace.joined(separator: "\n"))", file: file, line: line)
    }

    private func isVisibleInForm(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, !element.frame.isEmpty else { return false }
        return formViewport(in: app).contains(element.frame)
    }

    private func formViewport(in app: XCUIApplication) -> CGRect {
        let form = activeForm(in: app).frame.intersection(app.frame)
        let guideIsPresented = app.collectionViews["setup.form"].exists
        let navigationBar = guideIsPresented ? app.navigationBars["Set Up Hermes"] : app.navigationBars["hocket"]
        let top = max(form.minY, navigationBar.frame.maxY)
        let bottom = app.keyboards.firstMatch.exists ? min(form.maxY, app.keyboards.firstMatch.frame.minY) : form.maxY
        // Test actual visible bounds. An artificial inset made a fully visible,
        // hittable row 1.3 pt above that inset trigger alternating scrolls on Duo.
        // Drag endpoints already keep their own 20% margin inside this viewport.
        return CGRect(x: form.minX, y: top, width: form.width, height: max(0, bottom - top))
    }

    private func activeForm(in app: XCUIApplication) -> XCUIElement {
        // A sheet leaves the presenting Form in the accessibility tree. Scope
        // gestures to the guide, otherwise large-text tests drag the covered form.
        let guide = app.collectionViews["setup.form"]
        return guide.exists ? guide : app.collectionViews["connection.form"]
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
