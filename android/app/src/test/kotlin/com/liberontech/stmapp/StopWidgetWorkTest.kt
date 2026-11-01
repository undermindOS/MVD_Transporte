package com.liberontech.stmapp

import android.content.Context
import androidx.work.Configuration
import androidx.test.core.app.ApplicationProvider
import androidx.work.WorkManager
import androidx.work.WorkInfo
import es.antonborri.home_widget.HomeWidgetPlugin
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class StopWidgetWorkTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val manager get() = WorkManager.getInstance(context)

    @Before
    fun clear() {
        try {
            WorkManager.getInstance(context)
        } catch (_: IllegalStateException) {
            // Robolectric does not run AndroidX Startup providers.
            WorkManager.initialize(context, Configuration.Builder().build())
        }
        manager.cancelAllWork().result.get(10, TimeUnit.SECONDS)
        HomeWidgetPlugin.getData(context).edit().clear().commit()
    }

    private fun active() = manager.getWorkInfosForUniqueWork(StopWidgetWork.PERIODIC)
        .get(10, TimeUnit.SECONDS).filter { !it.state.isFinished }

    @Test
    fun intervalsChangeForAnExistingWidgetAndManualCancelsOnlyItsSchedule() {
        val prefs = HomeWidgetPlugin.getData(context)
        prefs.edit().putString("stop_board_574", "last-success").commit()
        StopWidgetWork.sync(context, 1)
        val id = active().single().id
        assertEquals(15 * 60_000L, active().single().periodicityInfo!!.repeatIntervalMillis)
        for (minutes in listOf(30, 60, 15)) {
            prefs.edit().putInt(StopWidgetWork.KEY_MINUTES, minutes).commit()
            StopWidgetWork.sync(context, 1)
            assertEquals(id, active().single().id)
            assertEquals(minutes * 60_000L, active().single().periodicityInfo!!.repeatIntervalMillis)
        }
        prefs.edit().putInt(StopWidgetWork.KEY_MINUTES, 0).commit()
        StopWidgetWork.sync(context, 1)
        assertTrue(active().isEmpty())
        assertEquals("last-success", prefs.getString("stop_board_574", null))
    }

    @Test
    fun multipleWidgetKindsShareOneTaskAndDeletingTheLastCancelsIt() {
        StopWidgetWork.sync(context, 3)
        StopWidgetWork.sync(context, 3)
        assertEquals(1, active().size)
        StopWidgetWork.sync(context, 0)
        assertTrue(active().isEmpty())
    }
}
