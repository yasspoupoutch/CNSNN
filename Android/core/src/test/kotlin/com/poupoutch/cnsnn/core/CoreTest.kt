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
        // 23:30 UTC on 13 October is already the 14th in Paris (UTC+2).
        assertEquals("2026-10-14", DailySchedule.key(Instant.parse("2026-10-13T23:30:00Z")))
        assertEquals("2026-10-13", DailySchedule.shift("2026-10-14", -1))
    }
    @Test fun formats() {
        assertEquals("1:05", Format.clock(65_400))
        assertEquals("1er", Format.ordinal(1)); assertEquals("12e", Format.ordinal(12))
        assertEquals("12 345", Format.number(12345))
        assertEquals("sans faute", Mistakes.text(0)); assertEquals("1 erreur", Mistakes.text(1)); assertEquals("3 erreurs", Mistakes.text(3))
        assertEquals("L", FriendCode.normalize("o0i1l"))
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
