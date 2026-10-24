package com.poupoutch.cnsnn.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UsageTest {
    @Test fun aNewPhoneCountsOnceADay() {
        var tally = UsageTally()
            .open("2026-10-25", "Android", returning = false)
            .open("2026-10-25", "Android", returning = false)
        assertEquals(mapOf("newAndroid" to 1, "opensAndroid" to 1), tally.pending["2026-10-25"])
        tally = tally.play("classic", "2026-10-25").play("classic", "2026-10-25").play("daily", "2026-10-25")
        assertEquals(mapOf("newAndroid" to 1, "opensAndroid" to 1, "players" to 1, "newPlayers" to 1, "classic" to 2, "daily" to 1), tally.pending["2026-10-25"])
        tally = tally.open("2026-10-26", "Android", returning = true).play("sprint", "2026-10-26")
        assertEquals(mapOf("opensAndroid" to 1, "players" to 1, "sprint" to 1), tally.pending["2026-10-26"])
    }

    @Test fun aPlayerUpdatingTheAppIsNotNew() {
        val tally = UsageTally().open("2026-10-25", "Android", returning = true).play("duo", "2026-10-25")
        assertEquals(mapOf("opensAndroid" to 1, "players" to 1, "duo" to 1), tally.pending["2026-10-25"])
    }

    @Test fun unknownModesAreIgnored() {
        assertTrue(UsageTally().play("players", "2026-10-25").play("other", "2026-10-25").pending.isEmpty())
    }

    @Test fun takeSendsOnlyOpeningsWithoutAccountAndDropsOldDays() {
        val tally = UsageTally().open("2026-10-20", "Android", returning = false)
            .open("2026-10-25", "Android", returning = false).play("survival", "2026-10-25")
        val (guest, waiting) = tally.take("2026-10-23", signedIn = false)
        assertEquals(mapOf("2026-10-25" to mapOf("opensAndroid" to 1)), guest)
        assertEquals(mapOf("2026-10-25" to mapOf("players" to 1, "newPlayers" to 1, "survival" to 1)), waiting.pending)
        val (player, done) = waiting.take("2026-10-23", signedIn = true)
        assertEquals(mapOf("2026-10-25" to mapOf("players" to 1, "newPlayers" to 1, "survival" to 1)), player)
        assertTrue(done.pending.isEmpty())
        assertTrue(done.take("2026-10-23", signedIn = true).first.isEmpty())
        // Saved on the phone between launches.
        assertEquals(waiting, UsageTally.fromJson(waiting.toJson()))
    }
}
