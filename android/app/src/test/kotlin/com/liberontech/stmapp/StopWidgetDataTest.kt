package com.liberontech.stmapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The rules of the stop widgets, on the JSON StopWidgetsFeed writes
// (test/stop_widgets_feed_test.dart pins the Dart side of the same keys).
class StopWidgetDataTest {
    private val t0 = 1_792_000_000_000L
    private val min = 60_000L

    private val saved = listOf(
        SavedStop(574, "SAN JOSE y ANDES"),
        SavedStop(3140, "AV RAMON ANADOR y TIBURCIO GOMEZ"),
        SavedStop(4018, "AV 18 DE JULIO y CONVENCION"),
    )

    private fun bus(line: String, dueMs: Long) = WidgetArrival(line, "POCITOS", "20:14", dueMs, false)

    @Test
    fun readsWhatTheAppWrites() {
        val stops = StopWidgetData.parseStops(
            """[{"id":574,"name":"SAN JOSE y ANDES"},{"id":3140,"name":"AV RAMON ANADOR y TIBURCIO GOMEZ"}]""")
        assertEquals(saved.take(2), stops)

        val board = StopWidgetData.parseBoard(
            """{"checkedAtMs":$t0,"arrivals":[{"line":"121","dest":"PUNTA CARRETAS","clock":"20:14","dueMs":${t0 + 60_000},"acc":true}]}""")!!
        assertEquals(t0, board.checkedAtMs)
        assertNull(board.failedAtMs)
        assertFalse(board.failed)
        assertEquals(WidgetArrival("121", "PUNTA CARRETAS", "20:14", t0 + 60_000, true), board.arrivals.single())
    }

    @Test
    fun badDataIsNoData() {
        assertEquals(emptyList<SavedStop>(), StopWidgetData.parseStops("not json"))
        assertEquals(emptyList<SavedStop>(), StopWidgetData.parseStops(null))
        assertNull(StopWidgetData.parseBoard("{"))
        assertNull(StopWidgetData.parseBoard(null))
        // A bus without a line or a due time is left out, the rest stays
        val board = StopWidgetData.parseBoard(
            """{"checkedAtMs":$t0,"arrivals":[{"dest":"X","dueMs":$t0},{"line":"116","clock":"20:19","dueMs":$t0}]}""")!!
        assertEquals(listOf("116"), board.arrivals.map { it.line })
        assertEquals("Línea 116", board.arrivals.single().destination)
    }

    @Test
    fun aFailureAfterTheLastGoodFetchIsFailed() {
        val failed = StopWidgetData.parseBoard("""{"checkedAtMs":$t0,"failedAtMs":${t0 + min},"arrivals":[]}""")!!
        assertTrue(failed.failed)
        val recovered = WidgetBoard(checkedAtMs = t0 + 2 * min, failedAtMs = t0 + min, arrivals = emptyList())
        assertFalse(recovered.failed)
        // Never fetched, failed once (the app writes a board with no buses)
        assertTrue(WidgetBoard(null, t0, emptyList()).failed)
    }

    @Test
    fun aWidgetShowsTheStopsItChoseThenTheFirstSaved() {
        assertEquals(listOf(574), StopWidgetData.pickStops(saved, emptyList(), 1).map { it.id })
        assertEquals(listOf(574, 3140), StopWidgetData.pickStops(saved, emptyList(), 2).map { it.id })
        assertEquals(listOf(4018), StopWidgetData.pickStops(saved, listOf(4018), 1).map { it.id })
        assertEquals(listOf(4018, 574), StopWidgetData.pickStops(saved, listOf(4018), 2).map { it.id })
        // A stop deleted in the app gives way to the first saved one
        assertEquals(listOf(574), StopWidgetData.pickStops(saved, listOf(9999), 1).map { it.id })
        // Never the same stop twice
        assertEquals(listOf(3140, 574), StopWidgetData.pickStops(saved, listOf(3140, 3140), 2).map { it.id })
        assertEquals(emptyList<Int>(), StopWidgetData.pickStops(emptyList(), listOf(574), 1).map { it.id })
        assertEquals(listOf(574, 3140), StopWidgetData.parseIds(" 574,3140,x,"))
    }

    @Test
    fun aTapMovesToTheNextSavedStopTheWidgetDoesNotShow() {
        val one = listOf(saved[0])
        assertEquals(listOf(3140), StopWidgetData.nextStop(saved, one, 0).map { it.id })
        assertEquals(listOf(574), StopWidgetData.nextStop(saved, listOf(saved[2]), 0).map { it.id })
        // Mis paradas shows 574 and 3140: the first slot skips 3140
        val two = saved.take(2)
        assertEquals(listOf(4018, 3140), StopWidgetData.nextStop(saved, two, 0).map { it.id })
        assertEquals(listOf(574, 4018), StopWidgetData.nextStop(saved, two, 1).map { it.id })
        // Nothing else saved: nothing moves
        assertEquals(two, StopWidgetData.nextStop(two, two, 0))
    }

    @Test
    fun aBusStaysAMinuteAfterItWasDue() {
        val board = WidgetBoard(t0, null, listOf(bus("116", t0 + 5 * min), bus("121", t0)))
        assertEquals(listOf("121", "116"), StopWidgetData.upcoming(board, t0 + min).map { it.line })
        assertEquals(listOf("116"), StopWidgetData.upcoming(board, t0 + min + 1).map { it.line })
        assertEquals(emptyList<String>(), StopWidgetData.upcoming(null, t0).map { it.line })
    }

    @Test
    fun anOldEmptyBoardAsksForARefresh() {
        assertTrue(StopWidgetData.isStale(null, t0))
        assertTrue(StopWidgetData.isStale(WidgetBoard(null, t0, emptyList()), t0))
        assertFalse(StopWidgetData.isStale(WidgetBoard(t0, null, emptyList()), t0 + 10 * min))
        assertTrue(StopWidgetData.isStale(WidgetBoard(t0, null, emptyList()), t0 + 10 * min + 1))
    }

    @Test
    fun theFooterSaysHowOldTheDataIs() {
        val a = WidgetBoard(t0, null, emptyList())
        val b = WidgetBoard(t0 - min, null, emptyList())
        // The oldest of the stops shown
        assertEquals(WidgetFooter.Checked(t0 - min), StopWidgetData.footer(listOf(a, b), null, t0))
        assertEquals(WidgetFooter.NoData, StopWidgetData.footer(listOf(null), null, t0))
        val failed = WidgetBoard(t0 - min, t0, emptyList())
        assertEquals(WidgetFooter.Failed(t0 - min), StopWidgetData.footer(listOf(a, failed), null, t0))
        assertEquals(WidgetFooter.Failed(null), StopWidgetData.footer(listOf(WidgetBoard(null, t0, emptyList())), null, t0))
    }

    @Test
    fun refreshingLastsUntilTheDataComesOrHalfAMinute() {
        val tap = t0
        val old = WidgetBoard(t0 - min, null, emptyList())
        assertEquals(WidgetFooter.Refreshing, StopWidgetData.footer(listOf(old), tap, t0 + 1_000))
        // New data came in after the tap
        val fresh = WidgetBoard(t0 + 2_000, null, emptyList())
        assertEquals(WidgetFooter.Checked(t0 + 2_000), StopWidgetData.footer(listOf(fresh), tap, t0 + 3_000))
        // The fetch failed after the tap
        val failed = WidgetBoard(t0 - min, t0 + 2_000, emptyList())
        assertEquals(WidgetFooter.Failed(t0 - min), StopWidgetData.footer(listOf(failed), tap, t0 + 3_000))
        // Nothing came: after 30 s the footer goes back to the old time
        assertEquals(WidgetFooter.Checked(t0 - min), StopWidgetData.footer(listOf(old), tap, t0 + 30_000))
    }

    @Test
    fun theWidgetIsRedrawnWhenSomethingChangesOnItsOwn() {
        val board = WidgetBoard(t0, null, listOf(bus("121", t0 + 2 * min), bus("116", t0 + 5 * min)))
        val shown = StopWidgetData.upcoming(board, t0)
        // The first bus to drop out
        assertEquals(t0 + 3 * min + 1, StopWidgetData.nextRedrawMs(shown, listOf(board), null, t0))
        // "Actualizando…" ends first
        assertEquals(t0 + 30_001, StopWidgetData.nextRedrawMs(shown, listOf(board), t0, t0))
        // Nothing shown: the board turning stale
        assertEquals(t0 + 10 * min + 1, StopWidgetData.nextRedrawMs(emptyList(), listOf(board), null, t0))
        assertNull(StopWidgetData.nextRedrawMs(emptyList(), listOf(null), null, t0))
    }
}
