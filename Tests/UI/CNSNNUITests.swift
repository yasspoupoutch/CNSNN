import XCTest
final class CNSNNUITests: XCTestCase {
    @MainActor func testLocalOnboardingAndNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let next = app.buttons["Continuer"]
        XCTAssertTrue(next.waitForExistence(timeout:5))
        next.tap()
        let field = app.textFields["Pseudo, entre 2 et 20 caractères"]
        XCTAssertTrue(field.waitForExistence(timeout:5))
        field.tap();field.typeText("Camille")
        app.buttons["C’est parti"].tap()
        XCTAssertTrue(app.buttons["Stats"].waitForExistence(timeout:5))
        app.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["Statistiques"].waitForExistence(timeout:5))
        app.buttons["Profil"].tap()
        XCTAssertTrue(app.staticTexts["Camille"].waitForExistence(timeout:5))
        app.buttons["Jouer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Mot du jour"].waitForExistence(timeout:5))
    }
}
