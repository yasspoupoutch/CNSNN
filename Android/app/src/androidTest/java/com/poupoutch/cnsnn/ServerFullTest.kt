package com.poupoutch.cnsnn

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.firebase.firestore.FirebaseFirestoreException
import com.poupoutch.cnsnn.data.CloudError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

/** The free Firestore quota used up for the day: a clear message, until midnight in California. */
@RunWith(AndroidJUnit4::class)
class ServerFullTest {
    @Test fun quotaStartsAgainAtMidnightInCalifornia() {
        // 23:30 in Paris on 27 October 2026: California is still on summer time (UTC-7).
        assertEquals(Instant.parse("2026-10-28T07:00:00Z"), CloudError.quotaReset(Instant.parse("2026-10-27T22:30:00Z")))
        // After the US clock change: midnight is 08:00 UTC, 9 h in Paris.
        assertEquals(Instant.parse("2026-11-11T08:00:00Z"), CloudError.quotaReset(Instant.parse("2026-11-10T12:00:00Z")))
    }

    @Test fun fullServerIsExplained() {
        val refused = FirebaseFirestoreException("Quota exceeded.", FirebaseFirestoreException.Code.RESOURCE_EXHAUSTED)
        assertEquals(CloudError.Code.SERVER_FULL, CloudError.code(refused))
        assertTrue(CloudError.message(refused).startsWith("Beaucoup de joueurs aujourd’hui"))
        assertEquals(CloudError.Code.SERVER_FULL, CloudError.code(CloudError(CloudError.Kind.SERVER_FULL)))
    }
}
