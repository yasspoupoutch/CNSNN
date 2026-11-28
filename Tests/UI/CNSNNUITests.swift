import XCTest
final class CNSNNUITests: XCTestCase {
    @MainActor func testLocalOnboardingAndNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--pseudo", "Camille"]
        app.launch()
        let start = app.buttons["C’est parti"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.buttons["Stats"].waitForExistence(timeout:5))
        app.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["Statistiques"].waitForExistence(timeout:5))
        app.buttons["Profil"].tap()
        XCTAssertTrue(app.staticTexts["Camille"].waitForExistence(timeout:5))
        // Profil > Proposer un mot opens the form in a sheet.
        app.buttons["profile.propose"].tap()
        XCTAssertTrue(app.staticTexts["Mes propositions"].waitForExistence(timeout:5))
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["profile.propose"].waitForExistence(timeout:5))
        // The Amis tab (no server in UI tests: the offline line).
        app.buttons["Amis"].tap()
        XCTAssertTrue(app.staticTexts["friends.offline"].waitForExistence(timeout:5))
        app.buttons["Jouer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Mot du jour"].waitForExistence(timeout:5))
    }

    /// First launch: no pseudo to type, no box to tick. The player plays as "Joueur…", and accepts the
    /// community rules only when choosing a pseudo.
    @MainActor func testFirstLaunchWithAutomaticPseudo() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let start = app.buttons["C’est parti"]
        XCTAssertTrue(start.waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["existing-account"].exists)
        start.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Joueur'")).firstMatch.waitForExistence(timeout:5))
        // No rules sheet at launch.
        XCTAssertFalse(app.buttons["rules.accept"].waitForExistence(timeout:2))
        let choose = app.buttons["home.choose-pseudo"]
        XCTAssertTrue(choose.waitForExistence(timeout:5))
        choose.tap()
        // The rules come first, then the pseudo box.
        let accept = app.buttons["rules.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout:5))
        accept.tap()
        let alert = app.alerts["Choisir mon pseudo"]
        XCTAssertTrue(alert.waitForExistence(timeout:5))
        alert.textFields.firstMatch.typeText("Camille")
        alert.buttons["Enregistrer"].tap()
        XCTAssertTrue(app.staticTexts["Camille"].firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["home.choose-pseudo"].exists)
    }

    /// New install: the ads measurement question once (nothing sent before "Oui"), then the switch in Profil.
    @MainActor func testAdMeasurementQuestionAndProfileSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--ask-ads", "--pseudo", "Camille"]
        app.launch()
        let alert = app.alerts["Aider CNSNN à se faire connaître ?"]
        XCTAssertTrue(alert.waitForExistence(timeout:8))
        alert.buttons["Non merci"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout:2))
        app.buttons["C’est parti"].tap()
        XCTAssertTrue(app.buttons["Profil"].waitForExistence(timeout:5))
        app.buttons["Profil"].tap()
        let toggle = app.switches["profile.adMeasurement"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout:5))
        XCTAssertEqual(toggle.value as? String, "0")
        // The switch itself sits at the right end of the row.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        // Asked once only: a relaunch goes straight to the game.
        app.terminate()
        app.launchArguments = ["--uitesting", "--pseudo", "Camille"]
        app.launch()
        XCTAssertFalse(app.alerts["Aider CNSNN à se faire connaître ?"].waitForExistence(timeout:3))
    }

    /// Survie, Sprint and Double sens from the home page: lives lost, a Sprint stopped, rounds skipped, results and records.
    @MainActor func testModesFromHome() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--mode-seed=42", "--pseudo", "Camille"]
        app.launch()
        let start = app.buttons["C’est parti"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
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

        // The DUEL card opens the duel sheet (offline here: it says so).
        let challenge = app.buttons["duelCard"]
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
        app.launchArguments = ["--uitesting", "--daily-found", "--pseudo", "Camille"]
        app.launch()
        let start = app.buttons["C’est parti"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let ranking = app.buttons["Classement"]
        XCTAssertTrue(ranking.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["19:51:25 · compté 10:00 au classement"].exists, "Un temps de plus d’une heure s’affiche en h:mm:ss, avec les 10 min comptées")
        let screen = app.windows.firstMatch.frame
        let elements: [(String, XCUIElement)] = [
            ("Bonjour", app.staticTexts["Bonjour,"]), ("Classement", ranking), ("Partager", app.buttons["Partager"]),
            ("Jouer aussi", app.staticTexts["JOUER AUSSI"]), ("Duel", app.buttons["duelCard"]), ("Tournoi", app.buttons["tournamentCard"]),
        ] + ["Classique", "Sprint"].map { title in
            (title, app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ".")).firstMatch)
        }
        for (name, element) in elements {
            XCTAssertTrue(element.exists, name)
            XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX, "\(name) dépasse à gauche")
            XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX, "\(name) dépasse à droite")
        }

        // Classique shows every category and difficulty as a chip, all on screen, and the one tapped is selected.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Classique.")).firstMatch.tap()
        let launch = app.buttons["Lancer une partie"]
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Toutes").count, 2)
        for title in ["Général", "Cinéma", "Géographie", "Animaux", "Objets", "Facile", "Moyen", "Difficile"] {
            let chip = app.buttons[title]
            XCTAssertTrue(chip.isHittable, title)
            XCTAssertLessThanOrEqual(chip.frame.maxX, screen.maxX, "\(title) dépasse à droite")
        }
        XCTAssertTrue(app.buttons.matching(identifier: "Toutes").firstMatch.isSelected)
        let easy = app.buttons["Facile"]
        easy.tap()
        XCTAssertTrue(easy.isSelected)
        XCTAssertFalse(app.buttons.matching(identifier: "Toutes").element(boundBy: 1).isSelected)
        launch.tap()
        XCTAssertTrue(app.buttons["Valider"].waitForExistence(timeout: 10))

        // Classique hints: the vowels, the sentence, then the vowels placed one by one; the last one shows the word.
        func hint(_ title: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch }
        hint("Indice").tap()
        XCTAssertTrue(app.staticTexts["Les voyelles du mot s’allument sur le clavier"].waitForExistence(timeout: 3))
        XCTAssertTrue(hint("Indice 2").waitForExistence(timeout: 3))
        hint("Indice 2").tap()
        var placed = 0
        while placed < 10, hint("Lettre").waitForExistence(timeout: 2) { hint("Lettre").tap(); placed += 1 }
        XCTAssertTrue(hint("Afficher le mot").waitForExistence(timeout: 3))
        hint("Afficher le mot").tap()
        let confirm = app.sheets.buttons["Afficher le mot"].exists ? app.sheets.buttons["Afficher le mot"] : app.buttons.matching(identifier: "Afficher le mot").element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Voici le mot."].waitForExistence(timeout: 5))
    }

    /// First-launch tutorial: the daily card and its Jouer button (tapped through the spotlight), then TR:
    /// TROU or AUTEUR, then Indice (tapped) with the theme and the clock. Profil > Revoir le tutoriel shows it again, and Passer closes it.
    @MainActor func testTutorial() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--tutorial", "--pseudo", "Camille"]
        app.launch()
        let start = app.buttons["C’est parti"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.staticTexts["Le mot du jour"].waitForExistence(timeout: 5))
        // Only Jouer, ringed in gold, goes on: it opens the real Mot du jour page.
        XCTAssertFalse(app.buttons["Suivant"].exists)
        let lit = app.buttons["tutorial.play"]
        XCTAssertTrue(lit.waitForExistence(timeout: 5))
        XCTAssertTrue(lit.isHittable)
        lit.tap()
        XCTAssertTrue(app.staticTexts["J’ai enlevé les voyelles"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Indice"].exists || app.staticTexts["Indice"].exists, "The real game page is behind")
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
        XCTAssertTrue(app.staticTexts["Le thème et le chrono"].waitForExistence(timeout: 5))
        app.buttons["Suivant"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Si vous ne trouvez pas…"].waitForExistence(timeout: 5))
        // Indice blinks; the real button lights the word's vowels (A, E, U) on the keyboard.
        app.buttons["Indice"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A, E et U s’allument")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["À vous de jouer"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["tutorial.skip"])], timeout: 5)
        // The real daily game opens next.
        let close = app.buttons["Fermer"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["« Il a écrit le livre. »"].exists)
        close.tap()

        app.buttons["Profil"].tap()
        let again = app.buttons["profile.tutorial"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        XCTAssertTrue(app.staticTexts["Le mot du jour"].waitForExistence(timeout: 5))
        app.buttons["tutorial.skip"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Le mot du jour"])], timeout: 5)
    }
}
