package com.poupoutch.cnsnn

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.poupoutch.cnsnn.data.LocalStore
import com.poupoutch.cnsnn.reminders.Reminders
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The 1.2 settings kept on the phone: the 12h reminder offer. */
@RunWith(AndroidJUnit4::class)
class LocalStoreTest {
    private val store = LocalStore(InstrumentationRegistry.getInstrumentation().targetContext)
    private val saved = store.remindersEnabled to store.reminderOffered

    @After fun restore() {
        store.remindersEnabled = saved.first; store.reminderOffered = saved.second
    }

    @Test fun reminderIsOfferedOnceToPlayersWithoutIt() {
        store.remindersEnabled = false; store.reminderOffered = false
        assertTrue(store.reminderOfferDue)
        store.reminderOffered = true
        assertFalse("Refused or accepted: never asked again", store.reminderOfferDue)
        store.reminderOffered = false; store.remindersEnabled = true
        assertFalse("Already on", store.reminderOfferDue)
        assertEquals(12 * 60, Reminders.DEFAULT_MINUTES)
    }
}
