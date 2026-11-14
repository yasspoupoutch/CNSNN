package com.poupoutch.cnsnn

import android.graphics.Bitmap
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.poupoutch.cnsnn.core.DuoGame
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.LocalStore
import com.poupoutch.cnsnn.state.ModeViewModel
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * A small phone (Galaxy S9: 360 × 740 dp, three-button bar), set up by tools/small-screen.sh:
 * the pseudo page shows its box to tick and its button above the keyboard, and Double sens shows both
 * clues above the answer, round after round, all without scrolling. Pictures go to files/shots.
 * Runs only when asked (`-e smallScreen true`).
 */
@RunWith(AndroidJUnit4::class)
class SmallScreenTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val notes = StringBuilder()

    private fun has(text: String, substring: Boolean = false) = rule.onAllNodes(hasText(text, substring = substring)).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(text: String, timeout: Long = 15_000) = rule.waitUntil(timeout) { has(text) }
    private fun bounds(node: SemanticsNodeInteraction): Rect = node.fetchSemanticsNode().boundsInWindow

    /** The bottom of what the player sees: the window less the keyboard (and the navigation bar under it). */
    private fun visibleBottom(): Float {
        var bottom = 0f
        rule.activityRule.scenario.onActivity { activity ->
            val view = activity.window.decorView
            val insets = ViewCompat.getRootWindowInsets(view)
            val ime = insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
            val bars = insets?.getInsets(WindowInsetsCompat.Type.navigationBars())?.bottom ?: 0
            bottom = (view.height - maxOf(ime, bars)).toFloat()
        }
        return bottom
    }

    private fun keyboardHeight(): Int {
        var ime = 0
        rule.activityRule.scenario.onActivity { activity ->
            ime = ViewCompat.getRootWindowInsets(activity.window.decorView)?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
        }
        return ime
    }

    private fun assertOnScreen(what: String, rect: Rect, bottom: Float) {
        val density = context.resources.displayMetrics.density
        notes.appendLine("$what : marge ${((bottom - rect.bottom) / density).toInt()} dp")
        assertTrue("$what est caché (bas ${rect.bottom}, visible jusqu’à $bottom)", rect.top >= 0f && rect.bottom <= bottom + 1f)
    }

    @Test fun everythingFitsWithoutScrolling() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("smallScreen") == "true")
        File(context.filesDir, "shots").deleteRecursively()
        try { run() } catch (e: Throwable) { runCatching { shot("zz-echec") }; throw e } finally { save() }
    }

    private fun run() {
        val metrics = context.resources.displayMetrics
        notes.appendLine("Écran : ${(metrics.widthPixels / metrics.density).toInt()} × ${(metrics.heightPixels / metrics.density).toInt()} dp")
        waitFor("Continuer")
        rule.onNodeWithText("Continuer").performClick()
        waitFor("Choisissez un pseudo")
        val accept = rule.onNodeWithContentDescription("J’accepte les règles de la communauté", substring = true)
        assertOnScreen("Case à cocher (sans clavier)", bounds(accept), visibleBottom())
        assertOnScreen("Bouton C’est parti (sans clavier)", bounds(rule.onNodeWithText("C’est parti")), visibleBottom())
        shot("01-pseudo")

        // The keyboard comes up: the box and the button stay above it.
        rule.onNodeWithText("Pseudo").performClick()
        rule.onNodeWithText("Pseudo").performTextInput("Alex")
        // The keyboard can take a moment on a slow emulator: a second tap on the field if need be.
        runCatching { rule.waitUntil(10_000) { keyboardHeight() > 0 } }.onFailure { rule.onNodeWithText("Pseudo").performClick() }
        rule.waitUntil(15_000) { keyboardHeight() > 0 }
        Thread.sleep(1_200)
        rule.waitForIdle()
        notes.appendLine("Clavier : ${(keyboardHeight() / metrics.density).toInt()} dp")
        assertOnScreen("Case à cocher (clavier ouvert)", bounds(accept), visibleBottom())
        assertOnScreen("Bouton C’est parti (clavier ouvert)", bounds(rule.onNodeWithText("C’est parti")), visibleBottom())
        assertOnScreen("Champ pseudo (clavier ouvert)", bounds(rule.onNodeWithText("Pseudo")), visibleBottom())
        accept.performClick()
        shot("02-pseudo-clavier")
        rule.onNodeWithText("C’est parti").performClick()

        waitFor("Bonjour,", 20_000)
        if (has("J’accepte")) rule.onNodeWithText("J’accepte").performClick()
        rule.skipTutorial()
        if (has("Non merci")) rule.onNodeWithText("Non merci").performClick()

        // Double sens: both clues above the answer, every round, before and after a word is found.
        val store = LocalStore(context)
        store.clearRun(PlayMode.DUO)
        // A draw with the longest clue of all (three lines): the hardest case for a small screen.
        val recent = store.recent(PlayMode.DUO)
        val longest = (1uL..2_000uL).first { seed -> DuoGame(seed, recent).duos.any { maxOf(it.first.hint.length, it.second.hint.length) >= 70 } }
        ModeViewModel.testSeed = longest
        val expected = DuoGame(longest, recent)
        rule.onNodeWithText("Double sens").performScrollTo().performClick()
        waitFor("Manche 1 sur 5")
        expected.duos.forEachIndexed { index, duo ->
            waitFor("Manche ${index + 1} sur 5")
            rule.waitForIdle()
            checkClues("Manche ${index + 1}")
            if (maxOf(duo.first.hint.length, duo.second.hint.length) >= 70) shot("06-double-sens-indice-long")
            if (index == 0) {
                shot("03-double-sens")
                WordEngine.normalize(duo.first.word).forEach { rule.onNodeWithContentDescription(it.toString()).performClick() }
                rule.onNodeWithText("Valider").performClick()
                rule.waitUntil(5_000) { rule.onAllNodes(hasContentDescription("Trouvé :", substring = true)).fetchSemanticsNodes().isNotEmpty() }
                Thread.sleep(1_500)
                checkClues("Manche 1, un mot trouvé")
                shot("04-double-sens-un-mot")
            }
            rule.onNodeWithText("Passer la manche").performClick()
            val next = if (index == expected.duos.lastIndex) "Voir le résultat" else "Manche suivante"
            waitFor(next)
            Thread.sleep(800)
            if (index == 0) shot("05-double-sens-reponses")
            rule.onNodeWithText(next).performClick()
        }
        waitFor("Partie terminée")
        rule.onNodeWithText("Accueil").performClick()
        waitFor("Bonjour,")

        // Sprint and Survie: the consonants, the theme and the whole hint above the answer, card after card.
        store.clearRun(PlayMode.SPRINT)
        rule.onNodeWithText("Sprint").performScrollTo().performClick()
        waitFor("90 secondes")
        repeat(8) { index ->
            checkHint("Sprint, carte ${index + 1}")
            if (index == 0) shot("07-sprint")
            rule.onNodeWithText("Passer · −5 s").performClick()
            Thread.sleep(400)
        }
        rule.onNodeWithContentDescription("Quitter").performClick()
        rule.onNodeWithText("Arrêter").performClick()
        waitFor("Accueil")
        rule.onNodeWithText("Accueil").performClick()
        waitFor("Bonjour,")

        store.clearRun(PlayMode.SURVIVAL)
        rule.onNodeWithText("Survie").performScrollTo().performClick()
        rule.waitUntil(10_000) { rule.onAllNodes(hasContentDescription("3 vies sur 3")).fetchSemanticsNodes().isNotEmpty() }
        repeat(3) { index ->
            checkHint("Survie, carte ${index + 1}")
            if (index == 0) shot("08-survie")
            rule.onNodeWithText("Passer · −1 vie").performClick()
            Thread.sleep(400)
        }
        waitFor("Accueil")
        rule.onNodeWithText("Accueil").performClick()
        waitFor("Bonjour,")

        // Classique with both hints shown.
        rule.onNodeWithText("Classique").performScrollTo().performClick()
        waitFor("Lancer une partie")
        rule.onNodeWithText("Lancer une partie").performClick()
        waitFor("votre réponse")
        rule.onNodeWithText("Indice").performClick()
        rule.waitForIdle()
        if (has("Indice 2")) rule.onNodeWithText("Indice 2").performClick()
        rule.waitUntil(5_000) { has("« ", substring = true) }
        Thread.sleep(800)
        checkHint("Classique, indices révélés")
        shot("09-classique-indice")
    }

    /** The hint sentence (« … ») and the consonants sit above the answer line, with no scrolling. */
    private fun checkHint(where: String) {
        rule.waitForIdle()
        Thread.sleep(300)
        val answer = bounds(rule.onNodeWithContentDescription("Votre réponse :", substring = true))
        val hints = rule.onAllNodes(hasText("« ", substring = true)).fetchSemanticsNodes()
        assertTrue("$where : pas d’indice à l’écran", hints.isNotEmpty())
        hints.forEach { assertOnScreen("$where, indice", it.boundsInWindow, answer.top) }
        val consonants = rule.onAllNodes(hasContentDescription("Consonnes :", substring = true)).fetchSemanticsNodes()
        assertTrue("$where : consonnes cachées", consonants.any { it.boundsInWindow.height > 20f })
    }

    private fun checkClues(round: String) {
        val answer = bounds(rule.onNodeWithContentDescription("Votre réponse :", substring = true))
        listOf(1, 2).forEach { n ->
            val clue = rule.onNode(hasContentDescription("Indice $n :", substring = true))
            assertOnScreen("$round, indice $n au-dessus de la réponse", bounds(clue), answer.top)
        }
        val consonants = rule.onNode(hasContentDescription("Consonnes :", substring = true))
        assertTrue("$round : consonnes cachées", bounds(consonants).height > 20f)
    }

    private fun shot(name: String) {
        rule.waitForIdle()
        Thread.sleep(700)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        val dir = File(context.filesDir, "shots").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun save() {
        val dir = File(context.filesDir, "shots").apply { mkdirs() }
        File(dir, "mesures.txt").writeText(notes.toString())
    }
}
