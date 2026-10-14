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
        // The start button waits for the community rules to be accepted.
        XCTAssertFalse(app.buttons["C’est parti"].isEnabled)
        app.buttons["accept-rules"].tap()
        app.buttons["C’est parti"].tap()
        XCTAssertTrue(app.buttons["Stats"].waitForExistence(timeout:5))
        app.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["Statistiques"].waitForExistence(timeout:5))
        app.buttons["Profil"].tap()
        XCTAssertTrue(app.staticTexts["Camille"].waitForExistence(timeout:5))
        app.buttons["Jouer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Mot du jour"].waitForExistence(timeout:5))
    }

    /// Survie, Sprint and Double sens from the home page: lives lost, a Sprint stopped, rounds skipped, results and records.
    @MainActor func testModesFromHome() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--mode-seed=42"]
        app.launch()
        let next = app.buttons["Continuer"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let field = app.textFields["Pseudo, entre 2 et 20 caractères"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Camille")
        app.buttons["accept-rules"].tap()
        app.buttons["C’est parti"].tap()
        func tile(_ title: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ".")).firstMatch }

        // Survie: three skips cost the three lives.
        let survival = tile("Survie")
        XCTAssertTrue(survival.waitForExistence(timeout: 5))
        survival.tap()
        let skipLife = app.buttons["Passer ce mot, une vie en moins"]
        XCTAssertTrue(skipLife.waitForExistence(timeout: 5))
        for _ in 0..<3 { skipLife.tap() }
        XCTAssertTrue(app.staticTexts["Plus de vies…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Rejouer"].exists)
        app.buttons["Accueil"].tap()

        // Sprint: a skip, then stopped; the game counts.
        let sprint = tile("Sprint")
        XCTAssertTrue(sprint.waitForExistence(timeout: 5))
        sprint.tap()
        let skipTime = app.buttons["Passer ce mot, 5 secondes de pénalité"]
        XCTAssertTrue(skipTime.waitForExistence(timeout: 5))
        skipTime.tap()
        app.buttons["Quitter"].tap()
        app.buttons["Arrêter le sprint"].tap()
        XCTAssertTrue(app.staticTexts["Sprint arrêté"].waitForExistence(timeout: 5))
        app.buttons["Accueil"].tap()

        // Double sens: five rounds given up, their words shown, then the results.
        let duo = tile("Double sens")
        XCTAssertTrue(duo.waitForExistence(timeout: 5))
        duo.tap()
        for round in 1...5 {
            let skipRound = app.buttons["Passer la manche et voir les mots"]
            XCTAssertTrue(skipRound.waitForExistence(timeout: 5))
            skipRound.tap()
            let go = app.buttons[round == 5 ? "Voir le résultat" : "Manche suivante"]
            XCTAssertTrue(go.waitForExistence(timeout: 5))
            go.tap()
        }
        XCTAssertTrue(app.staticTexts["Partie terminée"].waitForExistence(timeout: 5))
        app.buttons["Accueil"].tap()

        // The lilac tile opens the challenge sheet (offline here: it says so).
        let challenge = app.buttons["challengeTile"]
        XCTAssertTrue(challenge.waitForExistence(timeout: 5))
        challenge.tap()
        XCTAssertTrue(app.staticTexts["Mêmes 5 mots. Le plus rapide gagne."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connectez-vous à Internet pour défier vos amis."].exists)
        app.swipeDown(velocity: .fast)

        // The records page lists the three modes.
        app.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["Records personnels"].waitForExistence(timeout: 5))
    }
}
