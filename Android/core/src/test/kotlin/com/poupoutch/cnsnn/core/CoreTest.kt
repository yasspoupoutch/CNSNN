package com.poupoutch.cnsnn.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate

class WordEngineTest {
    @Test fun theBoardSeparatesWords() {
        assertEquals("L R LN", WordEngine.shownConsonants("Le Roi Lion"))
        assertEquals("– ST CHRL", WordEngine.shownConsonants("Où est Charlie ?"))
        assertEquals("MSSN MPSSBL", WordEngine.shownConsonants("Mission : Impossible"))
        assertEquals("LG D GLC", WordEngine.shownConsonants("L’Âge de glace"))
        assertEquals("SPDR MN", WordEngine.shownConsonants("Spider-Man"))
        assertEquals("RG GRG", WordEngine.shownConsonants("Rouge-gorge"))
        assertEquals("PPLLN", WordEngine.shownConsonants("Papillon"))
        assertEquals("L ; R ; L, N", WordEngine.spoken("L R LN"))
    }
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
    @Test fun dailyScoreIsTimeWithAMinuteForTheHint() {
        assertEquals(12_345, DailyScore.scoreMs(12_345, usedHint = false, correct = true))
        assertEquals(72_345, DailyScore.scoreMs(12_345, usedHint = true, correct = true))
        // Ten minutes at most, and a lost day counts ten minutes.
        assertEquals(600_000, DailyScore.scoreMs(580_000, usedHint = true, correct = true))
        assertEquals(600_000, DailyScore.scoreMs(9_000_000, usedHint = false, correct = true))
        assertEquals(600_000, DailyScore.scoreMs(3_000, usedHint = false, correct = false))
    }
    @Test fun dailyRankSortsTheDayThenTheTime() {
        // Days since 1970, the rules' dayIndex: 2024-01-01 is day 19 723 and DailySchedule's day 0.
        assertEquals(19_723L, DailyScore.dayIndex("2024-01-01"))
        assertEquals(LocalDate.parse("2026-10-16").toEpochDay(), DailyScore.dayIndex("2026-10-16"))
        assertEquals(DailySchedule.dayNumber("2026-10-16")!! + 19_723L, DailyScore.dayIndex("2026-10-16"))
        val base = DailyScore.dayBase("2026-10-16")!!
        assertEquals(20_742L * 1_000_000, base)
        assertEquals(base + 72_345, DailyScore.rank("2026-10-16", 72_345, true))
        assertEquals(base + 999_999, DailyScore.rank("2026-10-16", 600_000, false))
        // A found word in ten minutes still sorts before a lost day, and every day before the next.
        assertTrue(DailyScore.rank("2026-10-16", 600_000, true)!! < DailyScore.rank("2026-10-16", 600_000, false)!!)
        assertTrue(DailyScore.rank("2026-10-16", 600_000, false)!! < DailyScore.dayBase("2026-10-17")!!)
        assertNull(DailyScore.dayIndex("pas un jour"))
    }
    @Test fun monthIndexAndTotal() {
        assertEquals(2026 * 12 + 9, DailyScore.monthIndex("2026-10-16"))
        assertEquals(2027 * 12, DailyScore.monthIndex("2027-01-01"))
        assertEquals(DailyScore.monthIndex("2026-10-31")!! + 1, DailyScore.monthIndex("2026-11-01"))
        assertEquals(24_321L * 100_000_000 + 540_000, DailyScore.monthRank(24_321, 540_000))
        // Three days in: one word in 1 min (saved 9 min), the other days count 10 min each.
        assertEquals(21 * 60_000, DailyScore.monthTotal(540_000, 3))
        assertEquals(16, DailyScore.dayOfMonth("2026-10-16"))
    }
    @Test fun monthTallyFollowsTheRules() {
        val first = DailyScore.tally(DailyScore.Month(), "2026-10-14", 60_000)
        assertEquals(DailyScore.Month(DailyScore.monthIndex("2026-10-14")!!, 540_000, 1), first)
        val second = DailyScore.tally(first, "2026-10-15", 600_000)
        assertEquals(DailyScore.Month(first.month, 540_000, 2), second)
        // A new month starts from zero.
        val november = DailyScore.tally(second, "2026-11-01", 30_000)
        assertEquals(DailyScore.Month(first.month + 1, 570_000, 1), november)
        assertEquals((first.month + 1) * 100_000_000L + 570_000, november.rank)
        // A late result from the month before leaves the current month alone.
        assertEquals(november, DailyScore.tally(november, "2026-10-31", 10_000))
    }
    @Test fun classicLevelGrowsEveryTwentyWords() {
        assertEquals(1, ClassicLevel.level(0)); assertEquals(1, ClassicLevel.level(19)); assertEquals(2, ClassicLevel.level(20))
        assertEquals(5, ClassicLevel.into(45)); assertEquals(3, ClassicLevel.level(45))
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
        fun row(uid: String, month: Int?, today: Pair<Boolean, Int>?, hint: Boolean = false) = FriendStanding(uid, uid, month, 0,
            today?.let { Attempt(cardID = "x", mode = GameMode.DAILY, correct = it.first, timeMs = it.second, date = Instant.now(), dailyKey = "d") },
            todayScoreMs = today?.let { DailyScore.scoreMs(it.second, hint, it.first) }, todayHint = hint)
        // Found today first by today's time (the hint minute included), then the month total, lower first, none last.
        val ordered = FriendStanding.ordered(listOf(row("slow", 900_000, true to 9000), row("idle", null, null), row("fast", 5_000_000, true to 3000),
            row("hinted", 10, true to 2000, hint = true), row("miss", 1_200_000, false to 2000), row("steady", 800_000, null)))
        assertEquals(listOf("fast", "slow", "hinted", "steady", "miss", "idle"), ordered.map { it.uid })
    }
    @Test fun tallyFollowsTheRules() {
        val october = DailyScore.monthIndex("2026-10-14")!!
        val first = LeaderboardEntry.tally(null, "a", "A", "2026-10-14", true, 4000, 4000)
        assertEquals(1, first["streak"]); assertEquals(4000, first["bestTimeMs"]); assertFalse("points" in first)
        assertEquals(october, first["month"]); assertEquals(596_000, first["monthSaved"]); assertEquals(1, first["monthPlayed"])
        assertEquals(october * 100_000_000L + 596_000, first["monthRank"])
        // The keys the rules accept (updatedAt is added with the server time).
        assertEquals(setOf("uid", "username", "played", "wins", "streak", "bestStreak", "bestTimeMs", "lastWinDay", "lastResult", "month", "monthSaved", "monthPlayed", "monthRank"), first.keys)
        val old = LeaderboardEntry("a", "A", 1, 1, 1, 1, 4000, "2026-10-14", october, 596_000, 1)
        val next = LeaderboardEntry.tally(old, "a", "A", "2026-10-15", true, 9000, 69_000)
        assertEquals(2, next["streak"]); assertEquals(4000, next["bestTimeMs"])
        assertEquals(596_000 + 531_000, next["monthSaved"]); assertEquals(2, next["monthPlayed"])
        val lost = LeaderboardEntry.tally(old, "a", "A", "2026-10-15", false, 9000, 600_000)
        assertEquals(0, lost["streak"]); assertEquals("2026-10-14", lost["lastWinDay"])
        assertEquals(596_000, lost["monthSaved"]); assertEquals(2, lost["monthPlayed"])
        // A line from before monthly totals (month 0) starts this month from zero.
        val legacy = LeaderboardEntry("a", "A", 5, 4, 2, 3, 3000, "2026-09-30")
        val fresh = LeaderboardEntry.tally(legacy, "a", "A", "2026-10-01", true, 10_000, 10_000)
        assertEquals(october, fresh["month"]); assertEquals(590_000, fresh["monthSaved"]); assertEquals(1, fresh["monthPlayed"])
        // New month: reset. Late result from the month before: the month stays as it was.
        val november = LeaderboardEntry.tally(old, "a", "A", "2026-11-01", true, 1000, 1000)
        assertEquals(october + 1, november["month"]); assertEquals(599_000, november["monthSaved"]); assertEquals(1, november["monthPlayed"])
        val ahead = old.copy(month = october + 1, monthSaved = 599_000, monthPlayed = 1, lastWinDay = "2026-11-01")
        val late = LeaderboardEntry.tally(ahead, "a", "A", "2026-10-31", true, 1000, 1000)
        assertEquals(october + 1, late["month"]); assertEquals(599_000, late["monthSaved"]); assertEquals(1, late["monthPlayed"])
        assertEquals((october + 1) * 100_000_000L + 599_000, late["monthRank"])
    }
    @Test fun monthTotalOnlyForThisMonth() {
        val october = DailyScore.monthIndex("2026-10-14")!!
        val entry = LeaderboardEntry("a", "A", 2, 2, 2, 2, 4000, "2026-10-14", october, 1_000_000, 2)
        assertEquals(16 * 600_000 - 1_000_000, entry.monthTotalMs("2026-10-16"))
        assertNull(entry.monthTotalMs("2026-11-02"))
        assertNull(entry.copy(month = 0, monthSaved = 0, monthPlayed = 0).monthTotalMs("2026-10-16"))
    }
}

class ProgressJsonTest {
    // Written by the iPhone app (Swift JSONEncoder): dates in seconds since 2001, optionals left out.
    private val swiftJson = """{"username":"Yasin","attempts":[{"id":"A1","cardID":"seed-001","mode":"classic","correct":true,"timeMs":3000,"points":97,"date":782000000.5},{"id":"A2","cardID":"secret-2026-10-14","mode":"daily","correct":true,"timeMs":15000,"points":135,"date":782010000,"dailyKey":"2026-10-14"}],"recentCards":["seed-001"],"submissions":[],"dailyStarted":{"2026-10-14":"secret-2026-10-14"},"dailyStartedAt":{"2026-10-14":782009985},"dailyWords":{"2026-10-14":{"id":"secret-2026-10-14","wordFull":"Les Aristochats","hint":"Des chats de Disney.","category":"Cinéma","difficulty":"Moyen","status":"approved"}}}"""

    @Test fun readsTheIphoneProgress() {
        val progress = Progress.fromJson(swiftJson)
        assertEquals("Yasin", progress.username)
        assertEquals(2, progress.correctAnswers); assertEquals(1, progress.level); assertEquals(2, progress.levelInto)
        // Old points are still read (for the iPhone's copy), never added up.
        assertEquals(97, progress.attempts[0].points)
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
