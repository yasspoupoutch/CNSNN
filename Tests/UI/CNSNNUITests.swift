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
        // Profil > Ajouter un ami opens the friend code sheet (no server in UI tests: the offline line).
        app.buttons["profile.addFriend"].tap()
        XCTAssertTrue(app.staticTexts["Connectez-vous à Internet pour ajouter vos amis."].waitForExistence(timeout:5))
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["profile.addFriend"].waitForExistence(timeout:5))
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

        // Stats opens on the rankings; the player's own page lists the records of the three modes.
        app.buttons["Stats"].tap()
        let mine = app.buttons["Mes stats"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        mine.tap()
        XCTAssertTrue(app.staticTexts["Records personnels"].waitForExistence(timeout: 5))
    }

    /// The whole home page (greeting, daily card, challenge, mode tiles) stays inside the screen once today's
    /// word is found, even with the longest word and a time in hours.
    @MainActor func testHomeFitsScreenWithDailyFound() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--daily-found"]
        app.launch()
        let next = app.buttons["Continuer"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let field = app.textFields["Pseudo, entre 2 et 20 caractères"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Camille")
        app.buttons["accept-rules"].tap()
        app.buttons["C’est parti"].tap()

        let ranking = app.buttons["Classement"]
        XCTAssertTrue(ranking.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["19:51:25"].exists, "Un temps de plus d’une heure s’affiche en h:mm:ss")
        let screen = app.windows.firstMatch.frame
        let elements: [(String, XCUIElement)] = [
            ("Bonjour", app.staticTexts["Bonjour,"]), ("Classement", ranking), ("Partager", app.buttons["Partager"]),
            ("Jouer aussi", app.staticTexts["JOUER AUSSI"]), ("Défier un ami", app.buttons["challengeTile"]),
        ] + ["Classique", "Sprint"].map { title in
            (title, app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ".")).firstMatch)
        }
        for (name, element) in elements {
            XCTAssertTrue(element.exists, name)
            XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX, "\(name) dépasse à gauche")
            XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX, "\(name) dépasse à droite")
        }
    }

    /// First-launch tutorial: the daily card and its Jouer button (tapped through the spotlight), then TR:
    /// TROU but also AUTEUR, then the theme, the hint and the clock. Profil > Revoir le tutoriel shows it again, and Passer closes it.
    @MainActor func testTutorial() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--tutorial"]
        app.launch()
        let next = app.buttons["Continuer"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let field = app.textFields["Pseudo, entre 2 et 20 caractères"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Camille")
        app.buttons["accept-rules"].tap()
        app.buttons["C’est parti"].tap()

        XCTAssertTrue(app.staticTexts["Le mot du jour"].waitForExistence(timeout: 5))
        // The Jouer button, ringed in gold, goes on like Suivant.
        let lit = app.buttons["tutorial.play"]
        XCTAssertTrue(lit.waitForExistence(timeout: 5))
        XCTAssertTrue(lit.isHittable)
        lit.tap()
        XCTAssertTrue(app.staticTexts["J’ai enlevé les voyelles"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Consonnes : T, R"].exists)
        app.buttons["Suivant"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ça peut être TROU…"].waitForExistence(timeout: 5))
        app.buttons["Retour"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["J’ai enlevé les voyelles"].waitForExistence(timeout: 5))
        app.buttons["Suivant"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ça peut être TROU…"].waitForExistence(timeout: 5))
        app.buttons["Suivant"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["… ou AUTEUR…"].waitForExistence(timeout: 5))
        app.buttons["Suivant"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Thème, indice et chrono"].waitForExistence(timeout: 5))
        app.buttons["À vous de jouer"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["tutorial.skip"])], timeout: 5)
        XCTAssertTrue(app.staticTexts["Mot du jour"].waitForExistence(timeout: 5))

        app.buttons["Profil"].tap()
        let again = app.buttons["profile.tutorial"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        XCTAssertTrue(app.staticTexts["Le mot du jour"].waitForExistence(timeout: 5))
        app.buttons["tutorial.skip"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Le mot du jour"])], timeout: 5)
    }
}
