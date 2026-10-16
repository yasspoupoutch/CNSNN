import XCTest

/// App Store screenshots, run only by the "CNSNN - Captures App Store" workflow
/// (.github/workflows/ios-screenshots.yml). `--screenshots` fills the app with an invented profile,
/// rankings and challenges (App/Services/ScreenshotDemo.swift); every word on screen is a public
/// Classique card.
final class CNSNNScreenshotTests: XCTestCase {
    @MainActor func testAppStoreScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screenshots", "--mode-seed=7"]
        app.launch()

        // Onboarding, as in CNSNNUITests.
        let next = app.buttons["Continuer"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        let field = app.textFields["Pseudo, entre 2 et 20 caractères"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let color = app.buttons["Couleur 3"]
        if color.exists { color.tap() }
        field.tap(); field.typeText("Camille")
        app.buttons["accept-rules"].tap()
        app.buttons["C’est parti"].tap()

        // 1. Accueil: today's word found, Léa's challenge, the modes and their records.
        let ranking = app.buttons["Classement"]
        XCTAssertTrue(ranking.waitForExistence(timeout: 10))
        dismissKeyboardIfNeeded(app)
        capture("01-accueil")

        // 2. A Classique game in progress: the consonants, and an answer begun with its vowels in gold.
        let classic = tile(app, "Classique")
        XCTAssertTrue(classic.waitForExistence(timeout: 5))
        classic.tap()
        let launch = app.buttons["Lancer une partie"]
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        launch.tap()
        let close = app.buttons["Fermer"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Valider"].waitForExistence(timeout: 5))
        for letter in ["P", "A", "P", "I", "L"] { app.buttons[letter].firstMatch.tap() }
        capture("02-partie")
        close.tap()

        // 3. Classement: today's Mot du jour, "vous" among the others.
        XCTAssertTrue(ranking.waitForExistence(timeout: 10))
        ranking.tap()
        // Each row reads as one element ("1er, Léa, sans faute, 0:21").
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Léa")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        capture("03-classement")

        // 4. Mes stats: the official totals, the level and the tiles.
        let mine = app.buttons["Mes stats"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        mine.tap()
        XCTAssertTrue(app.staticTexts["Statistiques"].waitForExistence(timeout: 5))
        capture("04-stats")

        // 5. Sprint in play, its clock running.
        app.buttons["Jouer"].firstMatch.tap()
        let sprint = tile(app, "Sprint")
        XCTAssertTrue(sprint.waitForExistence(timeout: 10))
        sprint.tap()
        let skip = app.buttons["Passer ce mot, 5 secondes de pénalité"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        capture("05-sprint", settle: 3)
        app.buttons["Quitter"].tap()
        let stop = app.buttons["Arrêter le sprint"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        let home = app.buttons["Accueil"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.tap()

        // 6. Profil.
        let profile = app.buttons["Profil"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        XCTAssertTrue(app.staticTexts["Camille"].firstMatch.waitForExistence(timeout: 5))
        capture("06-profil")
    }

    /// A mode tile of the home page ("Sprint. 90 secondes…").
    @MainActor private func tile(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ".")).firstMatch
    }

    @MainActor private func dismissKeyboardIfNeeded(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        app.swipeDown(velocity: .fast)
    }

    /// Waits for the animations to settle, then keeps the whole screen in the test results.
    @MainActor private func capture(_ name: String, settle: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: settle)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
