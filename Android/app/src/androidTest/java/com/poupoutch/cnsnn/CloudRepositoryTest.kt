package com.poupoutch.cnsnn

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.Progress
import com.poupoutch.cnsnn.core.Attempt
import com.poupoutch.cnsnn.core.Scoring
import com.poupoutch.cnsnn.core.SecretDaily
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.data.CloudRepository
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant

/**
 * End-to-end checks of CloudRepository against the Firebase Auth and Firestore emulators, which
 * enforce the real Firebase/firestore.rules: the Android app must write exactly what the rules accept.
 */
@RunWith(AndroidJUnit4::class)
class CloudRepositoryTest {
    private val project = "demo-cnsnn"
    private val host = "10.0.2.2"
    private val docs = "http://$host:8080/v1/projects/$project/databases/(default)/documents"
    private lateinit var auth: FirebaseAuth
    private lateinit var repo: CloudRepository

    @Before fun setUp() = runBlocking<Unit> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        Cloud.useEmulators(context, host)
        val app = Cloud.app!!
        auth = FirebaseAuth.getInstance(app)
        repo = CloudRepository(auth, FirebaseFirestore.getInstance(app))
        auth.signOut()
        emulator("DELETE", "http://$host:8080/emulator/v1/projects/$project/databases/(default)/documents")
        emulator("DELETE", "http://$host:9099/emulator/v1/projects/$project/accounts")
    }

    @Test fun secretDailyWordIsCheckedByTheServer() = runBlocking<Unit> {
        val day = DailySchedule.key()
        seedSecret(day, "CHCLT", "Chocolat", "CHOCOLAT", "Un carré gourmand.")
        val alice = repo.bootstrap("Alice")
        assertTrue(alice.anonymous)
        val puzzle = repo.dailyPuzzle(day)!!
        assertEquals("CHCLT", puzzle.wordNoVowels); assertEquals("", puzzle.wordFull)
        // The word and the hint stay closed before the game.
        expectDenied { repo.dailySecret(day) }
        expectDenied { repo.dailyHint(day) }
        val session = repo.startDaily(alice.uid, day, SecretDaily.cardId(day))
        assertFalse(session.finished)
        // A second start would reset the clock: refused.
        expectDenied { repo.startDaily(alice.uid, day, SecretDaily.cardId(day)) }
        assertEquals("Un carré gourmand.", repo.revealSecretHint(alice.uid, day))
        // A win names a guess the server counted first.
        expectDenied { repo.finishDaily(alice.uid, day, true, 0, "CHOCOLAT") }
        delay(2100)
        // A wrong guess is counted, then cannot finish the game.
        assertEquals(1, repo.registerGuess(alice.uid, day, "CHOCOLAS"))
        // One guess per second at most.
        try { repo.registerGuess(alice.uid, day, "CHOCOLAT"); fail() } catch (e: CloudError) { assertEquals(CloudError.Kind.GUESS_TOO_SOON, e.kind) }
        expectDenied { repo.finishDaily(alice.uid, day, true, 0, "CHOCOLAS") }
        delay(1100)
        assertEquals(2, repo.registerGuess(alice.uid, day, "CHOCOLAT"))
        assertEquals(2, repo.dailySession(alice.uid, day)!!.guesses)
        // "Sans faute" cannot be forged: the wrong answers are the counted guesses.
        expectDenied { repo.finishDaily(alice.uid, day, true, 0, "CHOCOLAT") }
        assertTrue(repo.finishDaily(alice.uid, day, true, 1, "CHOCOLAT"))
        try { repo.registerGuess(alice.uid, day, "CHOCOLAT"); fail() } catch (e: CloudError) { assertEquals(CloudError.Kind.DAILY_FINISHED, e.kind) }
        assertEquals("Chocolat", repo.dailySecret(day)!!.wordFull)
        val official = repo.publishDailyResult(alice.uid, day)!!
        assertTrue(official.timeMs >= 1000)
        assertEquals(Scoring.points(DailySchedule.difficulty(day)!!, official.timeMs, true, true), official.points)
        assertEquals(official.timeMs, repo.publishDailyResult(alice.uid, day)!!.timeMs)
        val entry = repo.leaderboardEntry(alice.uid)!!
        assertEquals(official.points, entry.points); assertEquals(1, entry.played); assertEquals(1, entry.streak)
        val alone = repo.standing(day, official.timeMs, true)
        assertEquals(1, alone.players); assertEquals(1, alone.rank)
        assertEquals(listOf("Alice"), repo.dailyRanking(day).map { it.username })
        assertEquals(1, repo.wrongOf(alice.uid, day))
    }

    @Test fun givingUpRevealsTheWordAndCountsALoss() = runBlocking<Unit> {
        val day = DailySchedule.key()
        seedSecret(day, "CHCLT", "Chocolat", "CHOCOLAT", "Un carré gourmand.")
        val bob = repo.bootstrap("Bob")
        repo.startDaily(bob.uid, day, SecretDaily.cardId(day))
        assertEquals(1, repo.registerGuess(bob.uid, day, "TARTE"))
        // A loss carries exactly the counted guesses, and no answer.
        expectDenied { repo.finishDaily(bob.uid, day, false, 3) }
        assertTrue(repo.finishDaily(bob.uid, day, false, 1))
        assertEquals("Chocolat", repo.dailySecret(day)!!.wordFull)
        val result = repo.publishDailyResult(bob.uid, day)!!
        assertFalse(result.correct); assertEquals(0, result.points)
        assertEquals(0, repo.leaderboardEntry(bob.uid)!!.streak)
        assertEquals(1, repo.wrongOf(bob.uid, day))
    }

    @Test fun friendsCodeAndBoard() = runBlocking<Unit> {
        val alice = repo.bootstrap("Alice")
        val code = repo.friendCode(alice.uid, "Alice")
        assertEquals(6, code.length)
        assertEquals(code, repo.friendCode(alice.uid, "Alice"))
        auth.signOut()
        val bob = repo.bootstrap("Bob")
        try { repo.addFriend("ZZZZZZ", bob.uid); fail() } catch (e: CloudError) { assertEquals(CloudError.Kind.FRIEND_NOT_FOUND, e.kind) }
        assertEquals("Alice", repo.addFriend(code.lowercase(), bob.uid))
        val board = repo.friendsBoard(bob.uid, "Bob", DailySchedule.key())
        assertEquals(setOf("Alice", "Bob"), board.map { it.username }.toSet())
        repo.removeFriend(bob.uid, alice.uid)
        assertEquals(1, repo.friendsBoard(bob.uid, "Bob", DailySchedule.key()).size)
    }

    @Test fun proposalsAreUniqueAndRateLimited() = runBlocking<Unit> {
        val alice = repo.bootstrap("Alice")
        val card = Card("x", "Ornithorynque", "Un mammifère qui pond des œufs.", Category.entries.first(), Difficulty.entries.last())
        val stored = repo.submit(card, alice.uid)
        assertEquals("ORNITHORYNQUE", stored.id)
        assertEquals(1, repo.submissions(alice.uid).size)
        try { repo.submit(card.copy(hint = "Encore lui, une deuxième fois."), alice.uid); fail() }
        catch (e: CloudError) { assertEquals(CloudError.Kind.DUPLICATE_WORD, e.kind) }
        try { repo.submit(card.copy(wordFull = "Kangourou", hint = "Il saute très loin."), alice.uid); fail() }
        catch (e: CloudError) { assertEquals(CloudError.Kind.PROPOSAL_TOO_SOON, e.kind) }
        // Pending proposals stay private; approved cards are public and can be reported once.
        emulator("POST", "$docs/cards?documentId=KANGOUROU", """{"fields":{"wordFull":{"stringValue":"Kangourou"},"wordNoVowels":{"stringValue":"KNGR"},"normalizedAnswer":{"stringValue":"KANGOUROU"},"hint":{"stringValue":"Il saute très loin."},"category":{"stringValue":"Général"},"difficulty":{"stringValue":"Facile"},"createdBy":{"stringValue":"someone"},"status":{"stringValue":"approved"}}}""")
        auth.signOut(); repo.bootstrap("Bob")
        assertEquals(listOf("Kangourou"), repo.cards().map { it.wordFull })
        repo.report("KANGOUROU", "Ce mot est mal écrit")
        try { repo.report("KANGOUROU", "Encore une fois"); fail() } catch (e: CloudError) { assertEquals(CloudError.Kind.ALREADY_REPORTED, e.kind) }
    }

    @Test fun progressIsSharedWithTheIphoneFormat() = runBlocking<Unit> {
        val alice = repo.bootstrap("Alice")
        val progress = Progress(username = "Alice", attempts = listOf(Attempt(cardID = "seed-001", mode = GameMode.CLASSIC, correct = true, timeMs = 4200, points = 90, date = Instant.parse("2026-10-14T10:00:00Z"))))
        assertEquals(progress, repo.saveCloudProgress(progress, alice.uid))
        assertEquals(progress, repo.cloudProgress(alice.uid))
        // A second device that never saw the first game saves its own: both are kept.
        val other = Progress(username = "Alice", attempts = listOf(Attempt(cardID = "seed-002", mode = GameMode.CLASSIC, correct = false, timeMs = 9000, points = 0, date = Instant.parse("2026-10-14T11:00:00Z"))), rulesVersion = 1)
        val saved = repo.saveCloudProgress(other, alice.uid)
        assertEquals(setOf("seed-001", "seed-002"), saved.attempts.map { it.cardID }.toSet())
        assertEquals(1, saved.rulesVersion)
        assertEquals(saved, repo.cloudProgress(alice.uid))
    }

    @Test fun rulesAreAcceptedOnTheProfile() = runBlocking<Unit> {
        val alice = repo.bootstrap("Alice", rulesVersion = 1)
        assertEquals(1, alice.rulesVersion)
        assertEquals(1, repo.bootstrap("x").rulesVersion)
        auth.signOut()
        val bob = repo.bootstrap("Bob")
        assertNull(bob.rulesVersion)
        repo.acceptRules(bob.uid, 1)
        assertEquals(1, repo.bootstrap("x").rulesVersion)
    }

    @Test fun suspensionHidesWithoutErasing() = runBlocking<Unit> {
        val day = DailySchedule.key()
        seedSecret(day, "CHCLT", "Chocolat", "CHOCOLAT", "Un carré gourmand.")
        val alice = repo.bootstrap("Alice")
        val official = win(alice.uid, day)
        val card = Card("x", "Ornithorynque", "Un mammifère qui pond des œufs.", Category.entries.first(), Difficulty.entries.last())
        repo.submit(card, alice.uid)
        auth.signOut()
        val mod = repo.bootstrap("Modo")
        emulator("POST", "$docs/admins?documentId=${mod.uid}", """{"fields":{}}""")
        assertTrue(repo.isAdmin())
        if (official.timeMs < 5000) assertEquals(listOf(alice.uid), repo.suspiciousTimes(day).map { it.uid })
        // Approving a card moves the catalogue version, so phones download the cards again.
        assertNull(repo.cardsVersion())
        repo.review(repo.pendingCards().single(), true)
        assertTrue((repo.cardsVersion() ?: 0) > 0)

        repo.suspend(alice.uid, "Alice", "Temps suspect")
        assertTrue(repo.isSuspended(alice.uid))
        assertTrue(repo.topPlayers().none { it.uid == alice.uid })
        assertTrue(repo.fastestPlayers().none { it.uid == alice.uid })
        assertTrue(repo.dailyRanking(day).none { it.uid == alice.uid })
        assertTrue(repo.suspiciousTimes(day).none { it.uid == alice.uid })
        // Nothing is erased: totals and results stay.
        assertEquals(official.points, repo.leaderboardEntry(alice.uid, com.google.firebase.firestore.Source.SERVER)!!.points)
        assertEquals(official.timeMs, repo.dailyResult(alice.uid, day)!!.first.timeMs)

        repo.unsuspend(alice.uid)
        assertFalse(repo.isSuspended(alice.uid))
        assertEquals(listOf(alice.uid), repo.topPlayers().map { it.uid })
        assertEquals(listOf("Alice"), repo.dailyRanking(day).map { it.username })
    }

    @Test fun pseudoIsCheckedAndRenameUpdatesTheBoard() = runBlocking<Unit> {
        val alice = repo.bootstrap("Alice")
        expectDenied { repo.rename(alice.uid, "connard") }
        repo.rename(alice.uid, "Alicia")
        assertEquals("Alicia", repo.bootstrap("x").username)
    }

    @Test fun deletingTheAccountRemovesEverything() = runBlocking<Unit> {
        val day = DailySchedule.key()
        seedSecret(day, "CHCLT", "Chocolat", "CHOCOLAT", "Un carré gourmand.")
        // A permanent account, so Alice can come back after Bob reported her pseudo.
        val alice = repo.createPermanentAccount("alice@example.com", "motdepasse")
        win(alice.uid, day)
        repo.friendCode(alice.uid, "Alice")
        // More published cards than one batch used to anonymize (80).
        val words = (0 until 85).map { "CARTE" + ('A' + it / 26) + ('A' + it % 26) }
        val writes = words.joinToString(",") { word ->
            """{"update":{"name":"projects/$project/databases/(default)/documents/cards/$word","fields":{"wordFull":{"stringValue":"$word"},"wordNoVowels":{"stringValue":"CRT"},"normalizedAnswer":{"stringValue":"$word"},"hint":{"stringValue":"Une carte de test."},"category":{"stringValue":"Général"},"difficulty":{"stringValue":"Facile"},"createdBy":{"stringValue":"${alice.uid}"},"authorName":{"stringValue":"Alice"},"status":{"stringValue":"approved"}}}}"""
        }
        assertEquals(200, emulator("POST", "$docs:commit", """{"writes":[$writes]}"""))
        // A suspension and a report naming Alice go too.
        emulator("POST", "$docs/banned?documentId=${alice.uid}", """{"fields":{"username":{"stringValue":"Alice"},"reason":{"stringValue":"Test"}}}""")
        auth.signOut()
        val bob = repo.bootstrap("Bob")
        repo.reportPlayer(alice.uid, repo.leaderboardEntry(alice.uid)!!.username)
        auth.signOut()
        repo.signIn("alice@example.com", "motdepasse")
        repo.deleteAccount(alice.uid, "motdepasse")
        assertNull(auth.currentUser)
        // Read back as the emulator owner: nothing of Alice is left, only the tombstone.
        assertEquals(404, emulator("GET", "$docs/users/${alice.uid}"))
        assertEquals(404, emulator("GET", "$docs/leaderboard/${alice.uid}"))
        assertEquals(404, emulator("GET", "$docs/dailyResults/${alice.uid}_$day"))
        assertEquals(404, emulator("GET", "$docs/dailySessions/${alice.uid}_$day"))
        assertEquals(404, emulator("GET", "$docs/banned/${alice.uid}"))
        assertEquals(404, emulator("GET", "$docs/playerReports/${bob.uid}_${alice.uid}"))
        assertEquals(200, emulator("GET", "$docs/deletedUsers/${alice.uid}"))
        // Every published card stays, without her name or id.
        for (word in listOf(words.first(), words.last())) {
            val card = emulatorBody("$docs/cards/$word")
            assertTrue(card, card.contains("\"deleted\"")); assertFalse(card, card.contains("authorName")); assertFalse(card, card.contains(alice.uid))
        }
    }

    // ---- Helpers

    /** Plays and wins today's word the way the app does: guess counted first, no sooner than 2 s after the start. */
    private suspend fun win(uid: String, day: String): Attempt {
        repo.startDaily(uid, day, SecretDaily.cardId(day))
        delay(2100)
        assertEquals(1, repo.registerGuess(uid, day, "CHOCOLAT"))
        assertTrue(repo.finishDaily(uid, day, true, 0, "CHOCOLAT"))
        return repo.publishDailyResult(uid, day)!!
    }

    private fun emulatorBody(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.setRequestProperty("Authorization", "Bearer owner")
        connection.connectTimeout = 20_000; connection.readTimeout = 20_000
        return connection.inputStream.bufferedReader().use { it.readText() }.also { connection.disconnect() }
    }

    private suspend fun CloudRepository.wrongOf(uid: String, day: String): Int? = dailyResult(uid, day)?.second

    private suspend fun expectDenied(block: suspend () -> Unit) {
        try { block(); fail("Refus attendu") } catch (e: Exception) {
            if (e is AssertionError) throw e
            assertTrue("Refus attendu, reçu $e", CloudError.code(e) == CloudError.Code.PERMISSION_DENIED || e is FirebaseFirestoreException)
        }
    }

    private fun seedSecret(day: String, consonants: String, word: String, answer: String, hint: String) {
        val difficulty = DailySchedule.difficulty(day)!!.label
        emulator("POST", "$docs/dailyPuzzles?documentId=$day", """{"fields":{"consonants":{"stringValue":"$consonants"},"category":{"stringValue":"Général"},"difficulty":{"stringValue":"$difficulty"}}}""")
        emulator("POST", "$docs/dailyHints?documentId=$day", """{"fields":{"hint":{"stringValue":"$hint"}}}""")
        emulator("POST", "$docs/dailySecrets?documentId=$day", """{"fields":{"answer":{"stringValue":"$answer"},"word":{"stringValue":"$word"},"hint":{"stringValue":"$hint"},"category":{"stringValue":"Général"},"difficulty":{"stringValue":"$difficulty"}}}""")
    }

    /** Raw emulator call as "owner", which bypasses the security rules on the emulator only. */
    private fun emulator(method: String, url: String, body: String? = null): Int {
        repeat(3) { attempt ->
            try {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.requestMethod = method
                connection.setRequestProperty("Authorization", "Bearer owner")
                connection.connectTimeout = 20_000; connection.readTimeout = 20_000
                if (body != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.outputStream.use { it.write(body.toByteArray()) }
                }
                return connection.responseCode.also { connection.disconnect() }
            } catch (e: java.net.SocketTimeoutException) { if (attempt == 2) throw e }
        }
        error("unreachable")
    }

}
