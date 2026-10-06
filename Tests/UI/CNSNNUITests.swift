import XCTest
final class CNSNNUITests: XCTestCase {
    @MainActor func testLocalOnboardingAndNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let field = app.textFields["Pseudo, entre 2 et 20 caractères"]
        XCTAssertTrue(field.waitForExistence(timeout:5))
        field.tap();field.typeText("Camille")
        app.buttons["C’est parti"].tap()
        XCTAssertTrue(app.tabBars.buttons["Stats"].waitForExistence(timeout:5))
        app.tabBars.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["Chaque déclic compte."].exists)
        app.tabBars.buttons["Profil"].tap()
        XCTAssertTrue(app.staticTexts["Camille"].exists)
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Mot du jour"].exists)
    }
}
