package com.poupoutch.cnsnn

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The tutorial, opened again from Profil: the daily card with only its Jouer button lit, then the real
 * Mot du jour page: TR, TROU or AUTEUR, the theme and the clock, then Indice (tapped). Retour goes back a
 * step, "À vous de jouer" opens the real daily game.
 */
@RunWith(AndroidJUnit4::class)
class TutorialFlowTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private fun has(text: String) = rule.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(text: String) = rule.waitUntil(5_000) { has(text) }

    @Test fun tutorialFromProfile() {
        rule.waitUntil(15_000) { has("Continuer") || has("Bonjour,") }
        if (has("Continuer")) {
            rule.onNodeWithText("Continuer").performClick()
            rule.onNodeWithText("Pseudo").performTextInput("Tuto")
            rule.onNodeWithText("J’accepte les règles de la communauté", substring = true).performScrollTo().performClick()
            rule.onNodeWithText("C’est parti").performClick()
        }
        rule.waitUntil(20_000) { has("Bonjour,") }
        if (has("J’accepte")) rule.onNodeWithText("J’accepte").performClick()
        rule.skipTutorial()

        rule.onNodeWithText("Profil").performClick()
        rule.onNodeWithText("Revoir le tutoriel").performScrollTo().performClick()
        waitFor("Le mot du jour")
        // Only Jouer, ringed in gold, goes on: it opens the real Mot du jour page.
        assertFalse(has("Suivant"))
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("tutorial.play")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("tutorial.play").assertIsDisplayed().performClick()
        waitFor("J’ai enlevé les voyelles")
        rule.onNodeWithContentDescription("Consonnes : T, R").assertExists()
        rule.onNodeWithText("Suivant").performClick()
        waitFor("Ça peut être TROU…")
        rule.onNodeWithText("Retour").performClick()
        waitFor("J’ai enlevé les voyelles")
        rule.onNodeWithText("Suivant").performClick()
        waitFor("Ça peut être TROU…")
        rule.onNodeWithText("Suivant").performClick()
        waitFor("… ou AUTEUR…")
        rule.onNodeWithText("Suivant").performClick()
        waitFor("Le thème et le chrono")
        rule.onNodeWithText("Suivant").performClick()
        waitFor("Si vous ne trouvez pas…")
        // Indice blinks; tapping it really shows the hint on the game page.
        rule.onNodeWithTag("tutorial.hint").performClick()
        waitFor("« Il a écrit le livre. »")
        rule.onNodeWithText("À vous de jouer").performClick()
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("tutorial")).fetchSemanticsNodes().isEmpty() }
        // The real daily game opens next.
        rule.waitUntil(10_000) { rule.onAllNodes(androidx.compose.ui.test.hasContentDescription("Fermer")).fetchSemanticsNodes().isNotEmpty() }
        assertFalse(has("« Il a écrit le livre. »"))
        rule.onNodeWithContentDescription("Fermer").performClick()
        waitFor("Bonjour,")
    }
}
