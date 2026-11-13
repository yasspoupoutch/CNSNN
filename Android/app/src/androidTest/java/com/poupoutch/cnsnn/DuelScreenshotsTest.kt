package com.poupoutch.cnsnn

import android.graphics.Bitmap
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.firebase.auth.FirebaseAuth
import com.poupoutch.cnsnn.state.AppViewModel
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * The live duel's pictures, on the emulators: the "Défier un ami" sheet, then an invented duel against
 * Léa that plays on its own (LiveDuelViewModel "demo"): the search, the 3-2-1, both players moving
 * forward, the result, and the link for a friend. Runs only when asked (`-e duelScreenshots true`);
 * the PNG go to the app's files/shots folder.
 */
@RunWith(AndroidJUnit4::class)
class DuelScreenshotsTest {
    @get:Rule val rule = createEmptyComposeRule()
    private val host = "10.0.2.2"
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun has(text: String) = rule.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(text: String, timeout: Long = 20_000) = rule.waitUntil(timeout) { has(text) }

    @Test fun takeDuelScreenshots() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("duelScreenshots") == "true")
        File(context.filesDir, "shots").deleteRecursively()
        try { takeAll() } catch (e: Throwable) { runCatching { shot("zz-echec") }; throw e }
    }

    private fun takeAll() {
        Cloud.useEmulators(context, host)
        FirebaseAuth.getInstance(Cloud.app!!).signOut()
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        waitFor("Continuer")
        rule.onNodeWithText("Continuer").performClick()
        rule.onNodeWithText("Pseudo").performTextInput("Camille")
        rule.onNodeWithContentDescription("J’accepte les règles de la communauté", substring = true).performClick()
        rule.onNodeWithText("C’est parti").performClick()
        waitFor("Bonjour,")
        rule.skipTutorial()

        rule.onNodeWithTag("duelCard").performScrollTo()
        shot("duel-00-accueil")
        rule.onNodeWithTag("duelCard").performClick()
        rule.waitUntil(10_000) { rule.onAllNodes(hasTestTag("liveRandom")).fetchSemanticsNodes().isNotEmpty() }
        shot("duel-01-feuille")

        fun open(start: String) = scenario.onActivity { ViewModelProvider(it)[AppViewModel::class.java].liveDuelRequest = start }
        open("demo")
        waitFor("Recherche d’un adversaire…")
        shot("duel-02-recherche", settle = 800)
        waitFor("Duel contre")
        shot("duel-03-compte-a-rebours", settle = 600)
        waitFor("Valider")
        shot("duel-04-partie", settle = 6_000)
        shot("duel-05-partie-suite", settle = 6_000)
        waitFor("Terminer", 25_000)
        shot("duel-06-resultat")
        rule.onNodeWithText("Terminer").performClick()

        waitFor("Bonjour,")
        rule.onNodeWithTag("duelCard").performScrollTo().performClick()
        rule.waitUntil(10_000) { rule.onAllNodes(hasTestTag("liveFriend")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("liveFriend").performClick()
        rule.waitUntil(10_000) { rule.onAllNodes(hasTestTag("liveLink")).fetchSemanticsNodes().isNotEmpty() }
        shot("duel-07-ami")
        open("demo-link")
        waitFor("Envoyez ce code à un ami")
        shot("duel-08-lien")
    }

    private fun shot(name: String, settle: Long = 1_500) {
        if (has("Non merci")) rule.onNodeWithText("Non merci").performClick()
        Thread.sleep(settle)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: error("Capture impossible")
        val dir = File(context.filesDir, "shots").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
