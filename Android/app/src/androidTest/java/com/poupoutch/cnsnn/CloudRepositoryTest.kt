package com.poupoutch.cnsnn

import com.poupoutch.cnsnn.reminders.ChallengeWatch
import com.poupoutch.cnsnn.data.LocalStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.Challenge
import com.poupoutch.cnsnn.core.ChallengeInvite
import com.poupoutch.cnsnn.core.ChallengeRules
import com.poupoutch.cnsnn.core.ChallengeTally
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.DailyScore
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.Progress
import com.poupoutch.cnsnn.core.recordingMode
import com.poupoutch.cnsnn.core.records
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.ModeStat
import com.poupoutch.cnsnn.core.Attempt
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
        // The game asks for today's session first: a brand-new player gets "none", not a refusal.
        assertNull(repo.dailySession(alice.uid, day))
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
        assertEquals(official.timeMs, repo.publishDailyResult(alice.uid, day)!!.timeMs)
        // The hint was used: the official time adds a minute, and the month counts it.
        val scoreMs = DailyScore.scoreMs(official.timeMs, true, true)
        val entry = repo.leaderboardEntry(alice.uid)!!
        assertEquals(1, entry.played); assertEquals(1, entry.streak)
        assertEquals(DailyScore.monthIndex(day), entry.month); assertEquals(1, entry.monthPlayed)
        assertEquals(DailyScore.MISSED_MS - scoreMs, entry.monthSaved)
        val alone = repo.standing(day, DailyScore.rank(day, scoreMs, true)!!, true)
        assertEquals(1, alone.players); assertEquals(1, alone.rank)
        val ranking = repo.dailyRanking(day)
        assertEquals(listOf("Alice"), ranking.map { it.username })
        assertEquals(scoreMs, ranking.single().scoreMs); assertTrue(ranking.single().usedHint)
        assertEquals(listOf(alice.uid), repo.monthlyPlayers(day).map { it.uid })
        assertEquals(1 to 1, repo.monthlyRank(entry, day))
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
        assertFalse(result.correct)
        val entry = repo.leaderboardEntry(bob.uid)!!
        // A lost day counts ten minutes: nothing saved this month, and it sorts after every found word.
        assertEquals(0, entry.streak); assertEquals(0, entry.monthSaved); assertEquals(1, entry.monthPlayed)
        assertTrue(repo.dailyRanking(day).none { it.uid == bob.uid })
        assertEquals(1, repo.standing(day, DailyScore.rank(day, DailyScore.MISSED_MS, false)!!, false).players)
        assertEquals(1, repo.wrongOf(bob.uid, day))
    }

    @Test fun friendsCodeAndBoard() = runBlocking<Unit> {
        repo.bootstrap("Alice")
        val alice = repo.createPermanentAccount("friends.alice@example.com", "motdepasse")
        val code = repo.friendCode(alice.uid, "Alice")
        assertEquals(6, code.length)
        assertEquals(code, repo.friendCode(alice.uid, "Alice"))
        auth.signOut()
        val bob = repo.bootstrap("Bob")
        try { repo.addFriendByCode("ZZZZZZ", bob.uid, "Bob"); fail() } catch (e: CloudError) { assertEquals(CloudError.Kind.FRIEND_NOT_FOUND, e.kind) }
        assertEquals("Alice", repo.addFriendByCode(code.lowercase(), bob.uid, "Bob"))
        val board = repo.friendsBoard(bob.uid, "Bob", DailySchedule.key())
        assertEquals(setOf("Alice", "Bob"), board.map { it.username }.toSet())
        assertEquals(1, repo.friendCount(bob.uid))
        repo.removeFriend(bob.uid, alice.uid)
        assertEquals(1, repo.friendsBoard(bob.uid, "Bob", DailySchedule.key()).size)
        assertEquals(0, repo.friendCount(bob.uid))
        // Alice has Bob at once too, without typing his code.
        auth.signOut()
        repo.signIn("friends.alice@example.com", "motdepasse")
        assertEquals(1, repo.friendCount(alice.uid))
        assertEquals(listOf("Bob"), repo.friends(alice.uid).map { it.second })
        assertEquals(setOf("Alice", "Bob"), repo.friendsBoard(alice.uid, "Alice", DailySchedule.key()).map { it.username }.toSet())
    }

    /** A friend challenge from end to end, on the same documents as the iPhone app. */
    @Test fun friendChallengeFlow() = runBlocking<Unit> {
        repo.bootstrap("Alice")
        val alice = repo.createPermanentAccount("alice@example.com", "motdepasse")
        assertEquals("Alice", alice.username)
        val aliceCode = repo.friendCode(alice.uid, "Alice")
        auth.signOut()
        repo.bootstrap("Bob")
        val bob = repo.createPermanentAccount("bob@example.com", "motdepasse")
        val ids = ChallengeRules.draw(42uL)
        // Only a friend can be challenged.
        expectDenied { repo.createChallenge(bob.uid, "Bob", alice.uid, "Alice", ids) }
        repo.addFriendByCode(aliceCode, bob.uid, "Bob")
        val challenge = repo.createChallenge(bob.uid, "Bob", alice.uid, "Alice", ids)
        assertEquals(ids, challenge.cardIds)
        assertTrue(challenge.from.startedMs != null && challenge.to.startedMs == null)
        // Too fast for 5 words: refused. Bob skips all 5 (+100 s).
        expectDenied { repo.finishChallenge(challenge, bob.uid, 0, 0) }
        assertTrue(repo.finishChallenge(challenge, bob.uid, 5, 2))
        assertEquals(Challenge.State.Waiting, repo.challenges(bob.uid).single().state(bob.uid, System.currentTimeMillis()))
        // Ids start with the time: the background check finds it with a cursor, and only while it is recent.
        assertTrue(challenge.id.take(13).all { it.isDigit() })
        assertEquals(listOf(challenge.id), repo.recentChallenges(bob.uid, System.currentTimeMillis()).map { it.id })
        assertTrue(repo.recentChallenges(bob.uid, System.currentTimeMillis() + 60 * 3_600_000L).isEmpty())

        // Alice starts her clock (and gets Bob as a friend), finds 2 words and skips 3.
        auth.signOut()
        repo.signIn("alice@example.com", "motdepasse")
        val received = repo.challenges(alice.uid).single()
        assertEquals(Challenge.State.YourTurn, received.state(alice.uid, System.currentTimeMillis()))
        // The background check on Alice's phone: Bob's challenge once, in a few reads and well under a second or two.
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        LocalStore(context).challengeWatch = true
        val clock = System.currentTimeMillis()
        val alerts = ChallengeWatch.check(context, repo, paced = false)
        assertTrue("vérification trop longue", System.currentTimeMillis() - clock < 3_000)
        assertEquals(listOf(challenge.id + ".new"), alerts.map { it.key })
        assertEquals("Bob vous a défié !", alerts.single().title)
        assertTrue(ChallengeWatch.check(context, repo, paced = false).isEmpty())
        // Paced like in the background: no new read right after the last one.
        assertTrue(ChallengeWatch.check(context, repo).isEmpty())
        val started = repo.startChallenge(received, alice.uid)
        assertTrue(started.to.startedMs != null)
        assertEquals(listOf(bob.uid), repo.friends(alice.uid).map { it.first })
        expectDenied { repo.finishChallenge(started, alice.uid, 3, 0) }
        delay(4300)
        assertTrue(repo.finishChallenge(started, alice.uid, 3, 1))
        val over = repo.challenge(challenge.id)!!
        val now = System.currentTimeMillis()
        assertEquals(Challenge.Result.WON, over.result(alice.uid, now))
        assertEquals(Challenge.Result.LOST, over.result(bob.uid, now))
        assertEquals("1 victoire · 0 défaite", ChallengeTally.of(listOf(over), alice.uid, bob.uid, now).label)

        // Deleting Alice's account removes the challenge for Bob too.
        repo.deleteAccount(alice.uid, "motdepasse")
        repo.signIn("bob@example.com", "motdepasse")
        assertTrue(repo.challenges(bob.uid).isEmpty())
    }

    /** A challenge by link: Bob plays first, then Carol, who is not his friend, joins with the code. */
    @Test fun challengeByLinkFlow() = runBlocking<Unit> {
        repo.bootstrap("Bob")
        val bob = repo.createPermanentAccount("bob@example.com", "motdepasse")
        val open = repo.createOpenChallenge(bob.uid, "Bob", ChallengeRules.draw(7uL))
        val code = open.code!!
        assertTrue(open.isOpen)
        assertEquals(code, ChallengeInvite.code(ChallengeInvite.link(code)))
        expectKind(CloudError.Kind.INVITE_IS_YOURS) { repo.joinChallenge(code, bob.uid, "Bob") }
        assertTrue(repo.finishChallenge(open, bob.uid, 5, 0))

        auth.signOut()
        val carol = repo.bootstrap("Carol")
        expectKind(CloudError.Kind.INVITE_NOT_FOUND) { repo.joinChallenge("ZZZZZZ", carol.uid, "Carol") }
        val joined = repo.joinChallenge(code, carol.uid, "Carol")
        assertEquals(carol.uid, joined.to.uid)
        assertEquals(Challenge.State.YourTurn, joined.state(carol.uid, System.currentTimeMillis()))
        // Joining again is harmless; Bob is now Carol's friend, and the challenge is in her list.
        assertEquals(open.id, repo.joinChallenge(code, carol.uid, "Carol").id)
        assertEquals(listOf(bob.uid), repo.friends(carol.uid).map { it.first })
        assertEquals(listOf(open.id), repo.recentChallenges(carol.uid, System.currentTimeMillis()).map { it.id })
        assertTrue(repo.startChallenge(joined, carol.uid).to.startedMs != null)

        // Someone else is too late.
        auth.signOut()
        val dan = repo.bootstrap("Dan")
        expectKind(CloudError.Kind.INVITE_TAKEN) { repo.joinChallenge(code, dan.uid, "Dan") }

        // Bob sees who joined and adds Carol back; deleting his account removes the invite too.
        auth.signOut()
        repo.signIn("bob@example.com", "motdepasse")
        assertEquals("Carol", repo.challenge(open.id)!!.opponentName(bob.uid))
        repo.addFriend(bob.uid, carol.uid, "Carol")
        assertEquals(listOf(carol.uid), repo.friends(bob.uid).map { it.first })
        repo.deleteAccount(bob.uid, "motdepasse")
        auth.signOut()
        val erin = repo.bootstrap("Erin")
        expectKind(CloudError.Kind.INVITE_NOT_FOUND) { repo.joinChallenge(code, erin.uid, "Erin") }
    }

    private suspend fun expectKind(kind: CloudError.Kind, work: suspend () -> Unit) {
        try { work(); fail("Une erreur était attendue.") } catch (e: CloudError) { assertEquals(kind, e.kind) }
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

    /** Sprint, Survie and Double sens records: kept from both devices, counted once, back after a reinstall. */
    @Test fun modeRecordsSyncAcrossDevices() = runBlocking<Unit> {
        val lou = repo.bootstrap("Lou")
        var phone = Progress(username = "Lou")
            .recordingMode(PlayMode.SPRINT, mapOf(ModeStat.WORDS to 9, ModeStat.COMBO to 6), mapOf(ModeStat.GAMES to 1), "phone").first
            .recordingMode(PlayMode.DUO, mapOf(ModeStat.DUO to 599_957), mapOf(ModeStat.GAMES to 1, ModeStat.PERFECT to 1, ModeStat.DUOS_SOLVED to 5, ModeStat.DUOS_PLAYED to 5), "phone").first
        repo.saveCloudProgress(phone, lou.uid)
        val tablet = Progress(username = "Lou")
            .recordingMode(PlayMode.SPRINT, mapOf(ModeStat.WORDS to 7, ModeStat.COMBO to 7), mapOf(ModeStat.GAMES to 1), "tablet").first
            .recordingMode(PlayMode.SURVIVAL, mapOf(ModeStat.WORDS to 23, ModeStat.LEVEL to 5), mapOf(ModeStat.GAMES to 1), "tablet").first
        val merged = repo.saveCloudProgress(tablet, lou.uid)
        assertEquals(7, merged.records(PlayMode.SPRINT).best(ModeStat.COMBO))
        assertEquals(9, merged.records(PlayMode.SPRINT).best(ModeStat.WORDS))
        assertEquals(2, merged.records(PlayMode.SPRINT).total(ModeStat.GAMES))
        assertEquals(23, merged.records(PlayMode.SURVIVAL).best(ModeStat.WORDS))
        // Saving the same games again counts nothing twice.
        assertEquals(2, repo.saveCloudProgress(phone, lou.uid).records(PlayMode.SPRINT).total(ModeStat.GAMES))
        phone = phone.recordingMode(PlayMode.SPRINT, mapOf(ModeStat.WORDS to 5), mapOf(ModeStat.GAMES to 1), "phone").first
        repo.saveCloudProgress(phone, lou.uid)
        val restored = repo.cloudProgress(lou.uid)!!
        assertEquals(3, restored.records(PlayMode.SPRINT).total(ModeStat.GAMES))
        assertEquals(599_957, restored.records(PlayMode.DUO).best(ModeStat.DUO))
        assertEquals(1, restored.records(PlayMode.DUO).total(ModeStat.PERFECT))
        assertEquals(0, restored.correctAnswers)
        assertTrue(restored.attempts.isEmpty())
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
        assertTrue(repo.monthlyPlayers(day).none { it.uid == alice.uid })
        assertTrue(repo.fastestPlayers().none { it.uid == alice.uid })
        assertTrue(repo.dailyRanking(day).none { it.uid == alice.uid })
        assertTrue(repo.suspiciousTimes(day).none { it.uid == alice.uid })
        // Nothing is erased: totals and results stay.
        assertEquals(1, repo.leaderboardEntry(alice.uid, com.google.firebase.firestore.Source.SERVER)!!.monthPlayed)
        assertEquals(official.timeMs, repo.dailyResult(alice.uid, day)!!.first.timeMs)

        repo.unsuspend(alice.uid)
        assertFalse(repo.isSuspended(alice.uid))
        assertEquals(listOf(alice.uid), repo.monthlyPlayers(day).map { it.uid })
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
