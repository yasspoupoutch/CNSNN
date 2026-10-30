package com.poupoutch.cnsnn

import android.graphics.Bitmap
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.firebase.auth.FirebaseAuth
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.DailyScore
import com.poupoutch.cnsnn.core.SecretDaily
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant

/**
 * Google Play screenshots, taken in the real app on the emulators (never the production project):
 * today's word is a public Classique card and the other players of the ranking are made up.
 * Runs only when asked (`-e storeScreenshots true`); the PNG go to the app's files/shots folder.
 */
@RunWith(AndroidJUnit4::class)
class StoreScreenshotsTest {
    @get:Rule val rule = createEmptyComposeRule()
    private val project = "demo-cnsnn"
    private val host = "10.0.2.2"
    private val docs = "http://$host:8080/v1/projects/$project/databases/(default)/documents"
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun has(text: String) = rule.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(text: String, timeout: Long = 20_000) = rule.waitUntil(timeout) { has(text) }

    @Test fun takeStoreScreenshots() {
        try { takeAll() } catch (e: Throwable) { runCatching { shot("zz-echec") }; throw e }
    }

    private fun takeAll() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("storeScreenshots") == "true")
        Cloud.useEmulators(context, host)
        FirebaseAuth.getInstance(Cloud.app!!).signOut()
        emulator("DELETE", "http://$host:8080/emulator/v1/projects/$project/databases/(default)/documents")
        emulator("DELETE", "http://$host:9099/emulator/v1/projects/$project/accounts")
        val day = DailySchedule.key()
        seedDaily(day)
        listOf("Lina" to 34_000, "Hugo_R" to 47_000, "camille" to 58_000, "Mehdi" to 71_000, "Sarah.B" to 96_000, "Tom" to 124_000, "Nora" to 155_000)
            .forEachIndexed { i, (name, timeMs) -> seedResult(day, "demo$i", name, timeMs, usedHint = i == 3) }
        File(context.filesDir, "shots").deleteRecursively()

        ActivityScenario.launch(MainActivity::class.java)
        waitFor("Continuer")
        rule.onNodeWithText("Continuer").performClick()
        rule.onNodeWithText("Pseudo").performTextInput("Alex")
        rule.onNodeWithText("J’accepte les règles de la communauté", substring = true).performScrollTo().performClick()
        rule.onNodeWithText("C’est parti").performClick()
        waitFor("Bonjour,")
        rule.skipTutorial()
        shot("01-accueil")

        // Today's word, half typed, then found.
        rule.onNode(hasText("Jouer") and !isSelectable()).performClick()
        waitFor("Valider")
        "PARAP".forEach { rule.onNodeWithContentDescription(it.toString()).performClick() }
        shot("02-mot-du-jour")
        "LUIE".forEach { rule.onNodeWithContentDescription(it.toString()).performClick() }
        // The rules refuse an answer in the first two seconds of the game.
        Thread.sleep(2_500)
        rule.onNodeWithText("Valider").performClick()
        waitFor("Terminer")
        rule.waitUntil(20_000) { !has("Validation du temps officiel…") }
        shot("03-resultat")
        rule.onNodeWithText("Terminer").performClick()
        waitFor("Classement")
        rule.onNodeWithText("Classement").performClick()
        waitFor("Lina")
        shot("04-classement")

        // A Classique card from the home page.
        rule.onNodeWithText("Profil").performClick()
        waitFor("Proposer un mot")
        shot("06-profil")
        rule.onNode(hasText("Jouer") and isSelectable()).performClick()
        rule.onNodeWithText("Classique").performScrollTo().performClick()
        waitFor("Lancer une partie")
        rule.onNodeWithText("Lancer une partie").performClick()
        waitFor("Valider")
        shot("05-classique")
    }

    private fun shot(name: String) {
        // The midday reminder offer can come up on the way: not in the pictures.
        if (has("Non merci")) rule.onNodeWithText("Non merci").performClick()
        rule.waitForIdle()
        Thread.sleep(1_500)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: error("Capture impossible")
        val dir = File(context.filesDir, "shots").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    /** A public Classique card (never a secret word of the day) as today's word. */
    private fun seedDaily(day: String) {
        val difficulty = DailySchedule.difficulty(day)!!.label
        val hint = "Votre petit toit les jours de pluie."
        emulator("POST", "$docs/dailyPuzzles?documentId=$day", """{"fields":{"consonants":{"stringValue":"PRPL"},"category":{"stringValue":"Objets"},"difficulty":{"stringValue":"$difficulty"}}}""")
        emulator("POST", "$docs/dailyHints?documentId=$day", """{"fields":{"hint":{"stringValue":"$hint"}}}""")
        emulator("POST", "$docs/dailySecrets?documentId=$day", """{"fields":{"answer":{"stringValue":"PARAPLUIE"},"word":{"stringValue":"Parapluie"},"hint":{"stringValue":"$hint"},"category":{"stringValue":"Objets"},"difficulty":{"stringValue":"$difficulty"}}}""")
    }

    /** A made-up player's result, written like CloudRepository.publishDailyResult does. */
    private fun seedResult(day: String, uid: String, name: String, timeMs: Int, usedHint: Boolean) {
        val scoreMs = DailyScore.scoreMs(timeMs, usedHint, true)
        val rank = DailyScore.rank(day, scoreMs, true)!!
        val finished = Instant.now().minusSeconds(3_600)
        val started = finished.minusMillis(timeMs.toLong())
        emulator("POST", "$docs/dailyResults?documentId=${uid}_$day", """{"fields":{"userId":{"stringValue":"$uid"},"username":{"stringValue":"$name"},"day":{"stringValue":"$day"},""" +
            """"cardId":{"stringValue":"${SecretDaily.cardId(day)}"},"correct":{"booleanValue":true},"usedHint":{"booleanValue":$usedHint},"wrongAnswers":{"integerValue":"${if (usedHint) 1 else 0}"},""" +
            """"timeMs":{"integerValue":"$timeMs"},"scoreMs":{"integerValue":"$scoreMs"},"rank":{"integerValue":"$rank"},""" +
            """"startedAt":{"timestampValue":"$started"},"finishedAt":{"timestampValue":"$finished"}}}""")
    }

    /** Raw emulator call as "owner", which bypasses the security rules on the emulator only. */
    private fun emulator(method: String, url: String, body: String? = null): Int {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.setRequestProperty("Authorization", "Bearer owner")
        connection.connectTimeout = 20_000; connection.readTimeout = 20_000
        if (body != null) {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(body.toByteArray()) }
        }
        return connection.responseCode.also { connection.disconnect(); check(it < 300) { "$method $url : $it" } }
    }
}
