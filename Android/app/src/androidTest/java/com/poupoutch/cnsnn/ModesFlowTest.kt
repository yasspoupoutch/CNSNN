package com.poupoutch.cnsnn

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.poupoutch.cnsnn.core.DuoGame
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.SprintGame
import com.poupoutch.cnsnn.core.SurvivalGame
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.LocalStore
import com.poupoutch.cnsnn.state.ModeViewModel
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Sprint, Survie and Double sens played in the real app, on the emulators: right and wrong answers,
 * skips, lives, rounds, the results and the records on the home page. A fixed seed tells the test
 * which words come up (the same draw as the app's, with this phone's recent cards).
 */
@RunWith(AndroidJUnit4::class)
class ModesFlowTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private val seed = 42uL
    private val store get() = LocalStore(InstrumentationRegistry.getInstrumentation().targetContext)

    @Before fun fixSeed() { ModeViewModel.testSeed = seed }

    private fun has(text: String, substring: Boolean = false) = rule.onAllNodes(hasText(text, substring = substring)).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(text: String, timeout: Long = 10_000, substring: Boolean = false) = rule.waitUntil(timeout) { has(text, substring) }

    private fun waitForDescription(text: String) =
        rule.waitUntil(10_000) { rule.onAllNodes(hasContentDescription(text)).fetchSemanticsNodes().isNotEmpty() }

    private fun home() {
        rule.waitUntil(15_000) { has("Continuer") || has("Bonjour,") }
        if (has("Continuer")) {
            rule.onNodeWithText("Continuer").performClick()
            rule.onNodeWithText("Pseudo").performTextInput("Testeur")
            rule.onNodeWithText("J’accepte les règles de la communauté", substring = true).performScrollTo().performClick()
            rule.onNodeWithText("C’est parti").performClick()
        }
        waitFor("Bonjour,", 20_000)
        if (has("J’accepte")) rule.onNodeWithText("J’accepte").performClick()
        rule.waitUntil(5_000) { !has("J’accepte") }
    }

    private fun open(title: String) {
        rule.onNodeWithText(title).performScrollTo().performClick()
        waitFor(title)
    }

    private fun type(word: String) {
        WordEngine.normalize(word).forEach { rule.onNodeWithContentDescription(it.toString()).performClick() }
        rule.onNodeWithText("Valider").performClick()
        rule.waitForIdle()
    }

    /** The lilac tile opens the challenge sheet: rules, friends to challenge, and the invitation. */
    @Test fun challengeTileOpensTheSheet() {
        home()
        rule.onNodeWithTag("challengeTile").performScrollTo().performClick()
        waitFor("Mêmes 5 mots. Le plus rapide gagne.")
        waitFor("Inviter par message")
        // The friends list loads (earlier tests may leave a signed-in player who already has friends).
        rule.waitUntil(20_000) {
            !has("Chargement…") && (has("Ajoutez d’abord un ami", substring = true) || has("Connectez-vous à Internet", substring = true) ||
                rule.onAllNodes(hasContentDescription("Défier ", substring = true)).fetchSemanticsNodes().isNotEmpty())
        }
    }

    @Test fun sprintRightWrongSkipAndStop() {
        home()
        store.clearRun(PlayMode.SPRINT)
        val expected = SprintGame(seed, store.recent(PlayMode.SPRINT))
        open("Sprint")
        waitFor("90 secondes")
        // A right answer scores the card's points at ×1 and raises the combo.
        val first = expected.card!!
        type(first.wordFull)
        val points = SprintGame.basePoints(first.difficulty)
        waitForDescription("Score : ${Format.number(points)}")
        waitFor("×2")
        // A wrong answer keeps the word and resets the combo.
        type("XQ")
        waitFor("×1")
        rule.onNodeWithText("Passer · −5 s").performClick()
        // Stopping counts the game with its score.
        rule.onNodeWithContentDescription("Quitter").performClick()
        rule.onNodeWithText("Arrêter").performClick()
        waitFor("Sprint arrêté")
        waitFor("Premier record établi")
        rule.onNodeWithText("Rejouer").assertIsDisplayed()
        rule.onNodeWithText("Accueil").performClick()
        waitFor("Record $points pts", substring = true)
    }

    @Test fun survivalLivesAndEnd() {
        home()
        store.clearRun(PlayMode.SURVIVAL)
        val expected = SurvivalGame(seed, store.recent(PlayMode.SURVIVAL))
        open("Survie")
        waitForDescription("3 vies sur 3")
        type(expected.card!!.wordFull)
        waitFor("mot trouvé")
        // A wrong answer costs a life and keeps the word; a skip costs a life and moves on.
        type("XQ")
        waitForDescription("2 vies sur 3")
        rule.onNodeWithText("Passer · −1 vie").performClick()
        rule.onNodeWithText("Passer · −1 vie").performClick()
        waitFor("Plus de vies…")
        waitFor("Le dernier mot était", substring = true)
        rule.onNodeWithText("Accueil").performClick()
        waitFor("Record 1 mots", substring = true)
    }

    @Test fun survivalResumesAfterLeaving() {
        home()
        store.clearRun(PlayMode.SURVIVAL)
        val expected = SurvivalGame(seed, store.recent(PlayMode.SURVIVAL))
        open("Survie")
        type(expected.card!!.wordFull)
        // "Plus tard" keeps the game; the home page shows it in progress and it picks up there.
        rule.onNodeWithContentDescription("Quitter").performClick()
        rule.onNodeWithText("Plus tard").performClick()
        waitFor("Bonjour,")
        waitFor("En cours")
        open("Survie")
        waitFor("Partie reprise")
        rule.onNodeWithContentDescription("Quitter").performClick()
        rule.onNodeWithText("Abandonner").performClick()
        waitFor("Partie terminée")
        rule.onNodeWithText("Accueil").performClick()
    }

    @Test fun duoRoundsAndResults() {
        home()
        store.clearRun(PlayMode.DUO)
        val expected = DuoGame(seed, store.recent(PlayMode.DUO))
        open("Double sens")
        waitFor("Manche 1 sur 5")
        val duo = expected.duos.first()
        // Each answer fills the clue it matches, whatever the order.
        type(duo.second.word)
        type("XQ")
        type(duo.first.word)
        waitFor("Manche suivante")
        rule.onNodeWithText("Manche suivante").performClick()
        // The other rounds are skipped: their words are shown, then the next round.
        repeat(4) { index ->
            waitFor("Manche ${index + 2} sur 5")
            rule.onNodeWithText("Passer la manche").performClick()
            waitFor(if (index == 3) "Voir le résultat" else "Manche suivante")
            rule.onNodeWithText(if (index == 3) "Voir le résultat" else "Manche suivante").performClick()
        }
        waitFor("Partie terminée")
        rule.onNodeWithText("1/5").assertIsDisplayed()
        rule.onNodeWithText("2/10").assertIsDisplayed()
        rule.onNodeWithText("Accueil").performClick()
        waitFor("Bonjour,")
    }
}
