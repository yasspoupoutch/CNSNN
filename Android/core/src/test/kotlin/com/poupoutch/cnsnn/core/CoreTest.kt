package com.poupoutch.cnsnn.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class WordEngineTest {
    @Test fun consonants() {
        assertEquals("CHCLT", WordEngine.consonants("CHOCOLAT"))
        assertEquals("LPHNT", WordEngine.consonants("Éléphant"))
        assertEquals("LT", WordEngine.consonants("L’été"))
        assertEquals("F", WordEngine.consonants("œuf"))
        assertEquals("PNLT", WordEngine.consonants("Penalty"))
    }
    @Test fun frenchNormalization() {
        assertEquals("LOEUVREDETE", WordEngine.normalize("  L’ŒUVRE — d'Été  "))
        assertTrue(WordEngine.matches("les aristochats", "Les Aristochats"))
        assertFalse(WordEngine.matches("", "A"))
    }
    @Test fun vowels() {
        assertTrue(WordEngine.isVowel('É')); assertTrue(WordEngine.isVowel('y')); assertTrue(WordEngine.isVowel('Œ'))
        assertFalse(WordEngine.isVowel('C')); assertFalse(WordEngine.isVowel(' '))
    }
}

class NameFilterTest {
    @Test fun offensivePseudosAreRefused() {
        for (name in listOf("Connard", "gros c0nnard", "P.U.T.A.I.N", "Bâtard 93", "FDP", "pute", "Nazi", "S4lope")) assertFalse(name, NameFilter.isAllowed(name))
    }
    @Test fun ordinaryPseudosStay() {
        for (name in listOf("Monique", "Computer", "Nazim", "Constance", "Pedro", "Yasin", "Poupoutch", "Violette", "Montenegro", "Alexandre")) assertTrue(name, NameFilter.isAllowed(name))
    }
}

class GameRulesTest {
    @Test fun scoring() {
        assertEquals(150, Scoring.points(Difficulty.MEDIUM, 0, false, true))
        assertEquals(75, Scoring.points(Difficulty.MEDIUM, 0, true, true))
        assertEquals(50, Scoring.points(Difficulty.EASY, 90_000, false, true))
        assertEquals(0, Scoring.points(Difficulty.HARD, 1000, false, false))
    }
    @Test fun dailyCalendar() {
        assertEquals(Difficulty.EASY, DailySchedule.difficulty("2024-01-01"))   // Monday
        assertEquals(Difficulty.MEDIUM, DailySchedule.difficulty("2026-10-14")) // Wednesday
        assertEquals(Difficulty.HARD, DailySchedule.difficulty("2026-10-18"))   // Sunday
        // The word changes at each player's local midnight: 23:30 UTC on 13 October is already the
        // 14th in Paris (UTC+2), still the 13th in New York, and 1 hour of winter time later the same.
        val paris = java.time.ZoneId.of("Europe/Paris")
        assertEquals("2026-10-14", DailySchedule.key(Instant.parse("2026-10-13T23:30:00Z"), paris))
        assertEquals("2026-10-13", DailySchedule.key(Instant.parse("2026-10-13T23:30:00Z"), java.time.ZoneId.of("America/New_York")))
        assertEquals("2026-10-25", DailySchedule.key(Instant.parse("2026-10-24T22:30:00Z"), paris)) // summer time: UTC+2
        assertEquals("2026-10-25", DailySchedule.key(Instant.parse("2026-10-25T22:59:00Z"), paris)) // winter time: UTC+1
        assertEquals("2026-10-26", DailySchedule.key(Instant.parse("2026-10-25T23:00:00Z"), paris))
        // Midnight on the day the clocks go back is still a single midnight, 25 hours after the previous one.
        assertEquals(Instant.parse("2026-10-25T23:00:00Z"), DailySchedule.nextDay(Instant.parse("2026-10-25T12:00:00Z"), paris))
        assertEquals(Instant.parse("2026-03-28T23:00:00Z"), DailySchedule.nextDay(Instant.parse("2026-03-28T12:00:00Z"), paris))
        assertEquals(Instant.parse("2026-03-29T22:00:00Z"), DailySchedule.nextDay(Instant.parse("2026-03-29T12:00:00Z"), paris))
        assertEquals("2026-10-13", DailySchedule.shift("2026-10-14", -1))
    }
    @Test fun formats() {
        assertEquals("1:05", Format.clock(65_400))
        assertEquals("59:59", Format.clock(3_599_000))
        assertEquals("19:51:25", Format.clock(71_485_000))
        assertEquals("1er", Format.ordinal(1)); assertEquals("12e", Format.ordinal(12))
        assertEquals("12 345", Format.number(12345))
        assertEquals("sans faute", Mistakes.text(0)); assertEquals("1 erreur", Mistakes.text(1)); assertEquals("3 erreurs", Mistakes.text(3))
        assertEquals("L", FriendCode.normalize("o0i1l"))
    }
    @Test fun remainingGuessesAndSite() {
        assertNull(Guesses.remainingText(0)); assertNull(Guesses.remainingText(14))
        assertEquals("Plus que 5 essais", Guesses.remainingText(15))
        assertEquals("Plus qu’un essai", Guesses.remainingText(19))
        assertNull(Guesses.remainingText(20))
        assertEquals("Ajoute-moi sur CNSNN pour comparer nos temps au mot du jour : mon code ami est ABC234. https://cnsnn-9ctosy.web.app", Site.friendInvite("ABC234"))
        assertEquals(5, CommunityRules.items.size)
    }
    @Test fun seedCardsMatchTheIphone() {
        assertEquals(134, SeedCards.all.size); assertEquals("seed-000", SeedCards.all.first().id); assertEquals("Chocolat", SeedCards.all.first().wordFull)
        assertEquals(200, DailyPool.all.size); assertEquals("daily-e-001", DailyPool.all.first().id)
    }
    @Test fun topPercentAndFriends() {
        assertNull(DailyStanding(1, 200, null).topPercent)
        assertEquals(1, DailyStanding(2, 200, null).topPercent)
        assertNull(DailyStanding(150, 200, null).topPercent)
        fun row(uid: String, points: Int, today: Pair<Boolean, Int>?) = FriendStanding(uid, uid, points, 0,
            today?.let { Attempt(cardID = "x", mode = GameMode.DAILY, correct = it.first, timeMs = it.second, points = 0, date = Instant.now(), dailyKey = "d") })
        val ordered = FriendStanding.ordered(listOf(row("slow", 900, true to 9000), row("idle", 5000, null), row("fast", 10, true to 3000), row("miss", 100, false to 2000)))
        assertEquals(listOf("fast", "slow", "idle", "miss"), ordered.map { it.uid })
    }
    @Test fun tallyFollowsTheRules() {
        val first = LeaderboardEntry.tally(null, "a", "A", "2026-10-14", true, 4000, 146)
        assertEquals(1, first["streak"]); assertEquals(146, first["points"]); assertEquals(4000, first["bestTimeMs"])
        val old = LeaderboardEntry("a", "A", 146, 1, 1, 1, 1, 4000, "2026-10-14")
        val next = LeaderboardEntry.tally(old, "a", "A", "2026-10-15", true, 9000, 100)
        assertEquals(2, next["streak"]); assertEquals(4000, next["bestTimeMs"])
        val lost = LeaderboardEntry.tally(old, "a", "A", "2026-10-15", false, 9000, 0)
        assertEquals(0, lost["streak"]); assertEquals("2026-10-14", lost["lastWinDay"])
    }
}

class ProgressJsonTest {
    // Written by the iPhone app (Swift JSONEncoder): dates in seconds since 2001, optionals left out.
    private val swiftJson = """{"username":"Yasin","attempts":[{"id":"A1","cardID":"seed-001","mode":"classic","correct":true,"timeMs":3000,"points":97,"date":782000000.5},{"id":"A2","cardID":"secret-2026-10-14","mode":"daily","correct":true,"timeMs":15000,"points":135,"date":782010000,"dailyKey":"2026-10-14"}],"recentCards":["seed-001"],"submissions":[],"dailyStarted":{"2026-10-14":"secret-2026-10-14"},"dailyStartedAt":{"2026-10-14":782009985},"dailyWords":{"2026-10-14":{"id":"secret-2026-10-14","wordFull":"Les Aristochats","hint":"Des chats de Disney.","category":"Cinéma","difficulty":"Moyen","status":"approved"}}}"""

    @Test fun readsTheIphoneProgress() {
        val progress = Progress.fromJson(swiftJson)
        assertEquals("Yasin", progress.username)
        assertEquals(232, progress.score)
        assertEquals(Instant.parse("2025-10-12T22:13:20.500Z"), progress.attempts[0].date)
        assertEquals("Les Aristochats", progress.dailyWords!!["2026-10-14"]!!.wordFull)
        assertEquals(Category.CINEMA, progress.dailyWords!!["2026-10-14"]!!.category)
    }
    @Test fun writesWhatTheIphoneReads() {
        val json = Progress.fromJson(swiftJson).toJson()
        // Every non-optional Swift key is present, nil optionals are absent, dates stay numbers.
        for (key in listOf("\"username\"", "\"attempts\"", "\"recentCards\"", "\"submissions\"", "\"dailyStarted\"", "\"dailyStartedAt\"", "\"date\":")) assertTrue(key, json.contains(key))
        assertTrue(json, json.contains("\"date\":782000000.5") || json.contains("\"date\":7.820000005E8"))
        assertFalse(json.contains("null")); assertFalse(json.contains("\"author\""))
        assertEquals(Progress.fromJson(swiftJson), Progress.fromJson(json))
    }
    @Test fun mergeKeepsOneResultPerDay() {
        val mine = Progress.fromJson(swiftJson)
        val other = mine.copy(attempts = listOf(mine.attempts[1].copy(id = "B2", points = 1)), dailyWords = mapOf("2026-10-14" to mine.dailyWords!!["2026-10-14"]!!.copy(wordFull = "")))
        val merged = mine.merged(other)
        assertEquals(2, merged.attempts.size)
        assertEquals("Les Aristochats", merged.dailyWords!!["2026-10-14"]!!.wordFull)
    }
}

class ProgressMergeTest {
    private fun card(word: String, status: ReviewStatus) = Card(WordEngine.normalize(word), word, "Un indice assez long.", Category.GENERAL, Difficulty.EASY, status)
    private val t0 = Instant.parse("2026-10-14T10:00:00Z")

    @Test fun submissionsAreUnitedByWord() {
        // This device kept its local proposal (random id), the cloud copy has the server id and the review.
        val mine = Progress(submissions = listOf(
            Submission(id = "LOCAL-1", card = card("Kangourou", ReviewStatus.PENDING)),
            Submission(id = "LOCAL-2", card = card("Ornithorynque", ReviewStatus.APPROVED)),
            Submission(id = "LOCAL-3", card = card("Pélican", ReviewStatus.PENDING)),
        ))
        val cloud = Progress(submissions = listOf(
            Submission(id = "KANGOUROU", card = card("kangourou", ReviewStatus.APPROVED)),
            Submission(id = "ORNITHORYNQUE", card = card("Ornithorynque", ReviewStatus.PENDING)),
            Submission(id = "PELICAN", card = card("Pelican", ReviewStatus.PENDING)),
            Submission(id = "TATOU", card = card("Tatou", ReviewStatus.REJECTED)),
        ))
        val merged = mine.merged(cloud)
        assertEquals(listOf("KANGOUROU", "ORNITHORYNQUE", "PELICAN", "TATOU"), merged.submissions.map { it.word })
        // Reviewed beats pending, whichever side has it; otherwise this device's copy stays.
        assertEquals("KANGOUROU", merged.submissions[0].id); assertEquals(ReviewStatus.APPROVED, merged.submissions[0].card.status)
        assertEquals("LOCAL-2", merged.submissions[1].id)
        assertEquals("LOCAL-3", merged.submissions[2].id)
        // Merging again changes nothing.
        assertEquals(merged.submissions, merged.merged(cloud).submissions)
    }

    @Test fun rulesVersionKeepsTheHighest() {
        assertNull(Progress().merged(Progress()).rulesVersion)
        assertEquals(1, Progress().merged(Progress(rulesVersion = 1)).rulesVersion)
        assertEquals(2, Progress(rulesVersion = 2).merged(Progress(rulesVersion = 1)).rulesVersion)
        assertEquals(1, Progress(rulesVersion = 1).merged(Progress()).rulesVersion)
        // Optional in the shared JSON: absent while null, read back when set.
        assertFalse(Progress().toJson().contains("rulesVersion"))
        assertEquals(1, Progress.fromJson(Progress(rulesVersion = 1).toJson()).rulesVersion)
        assertTrue(CommunityRules.mustAccept(Progress(username = "Alice")))
        assertFalse(CommunityRules.mustAccept(Progress(username = "Alice", rulesVersion = 1)))
        assertFalse(CommunityRules.mustAccept(Progress()))
    }

    @Test fun twoDevicesKeepEveryGame() {
        val shared = Attempt(id = "S", cardID = "seed-001", mode = GameMode.CLASSIC, correct = true, timeMs = 3000, points = 90, date = t0)
        fun classic(id: String, minutes: Long) = Attempt(id = id, cardID = "seed-$id", mode = GameMode.CLASSIC, correct = true, timeMs = 5000, points = 80, date = t0.plusSeconds(minutes * 60))
        fun daily(id: String, day: String, points: Int) = Attempt(id = id, cardID = SecretDaily.cardId(day), mode = GameMode.DAILY, correct = true, timeMs = 9000, points = points, date = t0, dailyKey = day)
        // Phone A and phone B, same account, each played offline after the last sync.
        val phoneA = Progress(username = "Alice", attempts = listOf(shared, classic("A1", 1), classic("A2", 3), daily("DA", "2026-10-14", 140)), rulesVersion = 1)
        val phoneB = Progress(username = "Alice", attempts = listOf(shared, classic("B1", 2), daily("DB", "2026-10-14", 1), daily("DB2", "2026-10-13", 120)))
        // A saves first, then B saves over the cloud copy: each save merges with what is there.
        val cloudAfterA = phoneA.merged(Progress())
        val cloudAfterB = phoneB.merged(cloudAfterA)
        assertEquals(setOf("S", "A1", "A2", "B1", "DB", "DB2"), cloudAfterB.attempts.map { it.id }.toSet())
        // One result per day, and history sorted by date.
        assertEquals(1, cloudAfterB.attempts.count { it.dailyKey == "2026-10-14" })
        assertEquals(cloudAfterB.attempts.sortedBy { it.date }, cloudAfterB.attempts)
        assertEquals(1, cloudAfterB.rulesVersion)
        // A pulls the cloud copy back: both phones now hold the same games.
        val backOnA = phoneA.merged(cloudAfterB)
        assertEquals(cloudAfterB.attempts.map { it.id }.toSet() - "DB" + "DA", backOnA.attempts.map { it.id }.toSet())
        assertEquals(6, backOnA.attempts.size)
    }
}

class GlanceTest {
    private val noon = java.time.Instant.parse("2026-10-14T10:00:00Z")
    @Test fun streakAndToday() {
        val progress = Progress(attempts = listOf(
            Attempt(cardID = "a", mode = GameMode.DAILY, correct = true, timeMs = 9000, points = 10, date = noon, dailyKey = "2026-10-13"),
        ))
        val glance = Glance.of(progress, 3)
        assertFalse(glance.playedToday(noon)); assertEquals(3, glance.currentStreak(noon))
        assertEquals(0, glance.currentStreak(noon.plusSeconds(2 * 86_400)))
        assertEquals(glance, Glance.fromJson(glance.toJson()))
    }
}
