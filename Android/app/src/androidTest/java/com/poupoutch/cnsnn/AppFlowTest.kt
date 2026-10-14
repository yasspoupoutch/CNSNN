package com.poupoutch.cnsnn

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The real app, on the emulators: onboarding, then a Classique card played with the in-game keyboard. */
@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()

    @Test fun onboardingThenClassicGame() {
        rule.waitUntil(15_000) { rule.onAllNodes(hasText("Continuer")).fetchSemanticsNodes().isNotEmpty() || rule.onAllNodes(hasText("Bonjour,")).fetchSemanticsNodes().isNotEmpty() }
        if (rule.onAllNodes(hasText("Continuer")).fetchSemanticsNodes().isNotEmpty()) {
            rule.onNodeWithText("Continuer").performClick()
            rule.onNodeWithText("Pseudo").performTextInput("Testeur")
            rule.onNodeWithText("C’est parti").performClick()
        }
        rule.waitUntil(20_000) { rule.onAllNodes(hasText("Bonjour,")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("Lancer une partie").performClick()
        rule.waitUntil(10_000) { rule.onAllNodes(hasText("votre réponse")).fetchSemanticsNodes().isNotEmpty() }
        // A wrong answer stays in the game and is shown crossed out.
        rule.onNodeWithContentDescription("X").performClick()
        rule.onNodeWithContentDescription("Q").performClick()
        rule.onNodeWithText("Valider").performClick()
        rule.waitUntil(5_000) { rule.onAllNodes(hasText("XQ")).fetchSemanticsNodes().isNotEmpty() }
        // Hint, then give up: the result sheet shows the word.
        rule.onNodeWithText("Indice  points ÷ 2").performClick()
        rule.onNodeWithText("Passer").performClick()
        rule.onNodeWithText("Révéler le mot").performClick()
        rule.waitUntil(5_000) { rule.onAllNodes(hasText("Pas cette fois…")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("Mot suivant").assertIsDisplayed()
        rule.onNodeWithText("Retour à l’accueil").performClick()
        rule.waitUntil(5_000) { rule.onAllNodes(hasText("1 mots trouvés")).fetchSemanticsNodes().isNotEmpty() || rule.onAllNodes(hasText("0 mots trouvés")).fetchSemanticsNodes().isNotEmpty() }
    }
}
