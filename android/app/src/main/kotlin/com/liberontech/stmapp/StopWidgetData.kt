package com.liberontech.stmapp

import org.json.JSONArray
import org.json.JSONObject

/** A stop saved in Mis paradas (`stops_saved`, written by StopWidgetsFeed). */
data class SavedStop(val id: Int, val name: String)

/** One bus of a board: its due time is on the phone's clock. */
data class WidgetArrival(
    val line: String,
    val destination: String,
    /** The source's clock time at the stop, "H:MM". */
    val clock: String,
    val dueMs: Long,
    val accessible: Boolean,
)

/** A stop's board as the app last wrote it (`stop_board_{id}`). */
data class WidgetBoard(
    /** Last good fetch, on the phone's clock; null if never fetched. */
    val checkedAtMs: Long?,
    /** Last failed fetch, on the phone's clock. */
    val failedAtMs: Long?,
    val arrivals: List<WidgetArrival>,
) {
    val failed: Boolean
        get() = failedAtMs != null && (checkedAtMs == null || failedAtMs > checkedAtMs)
}

/** What the footer of a widget says. */
sealed class WidgetFooter {
    /** "Datos de las 20:13". */
    data class Checked(val atMs: Long) : WidgetFooter()

    /** "No se pudo actualizar. Datos de las 19:58." ([atMs] null: never). */
    data class Failed(val atMs: Long?) : WidgetFooter()

    /** "Actualizando…": the refresh button was tapped. */
    object Refreshing : WidgetFooter()

    /** Nothing fetched yet: "Tocá para actualizar". */
    object NoData : WidgetFooter()
}

/**
 * The rules of the stop widgets, without Android: which stops a widget
 * shows, which buses are still to come, what the footer says and when to
 * redraw. TimbreStopWidget draws the result.
 */
object StopWidgetData {
    /** A bus stays this long after it was due, as in Mis paradas. */
    const val EXPIRED_AFTER_MS = 60 * 1000L

    /** An empty board older than this asks for a refresh instead of
     *  saying no bus is coming: its buses may just have passed. */
    const val STALE_AFTER_MS = 10 * 60 * 1000L

    /** "Actualizando…" shows at most this long after a tap. */
    const val REFRESHING_FOR_MS = 30 * 1000L

    /** Taps on refresh closer than this ask for data once. */
    const val REFRESH_GAP_MS = 15 * 1000L

    fun parseStops(json: String?): List<SavedStop> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { i ->
                val stop = array.optJSONObject(i) ?: return@mapNotNull null
                val id = stop.optInt("id", -1)
                if (id < 0) null else SavedStop(id, stop.optString("name", "Parada $id"))
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun parseBoard(json: String?): WidgetBoard? {
        if (json.isNullOrEmpty()) return null
        return try {
            val board = JSONObject(json)
            val arrivals = board.optJSONArray("arrivals") ?: JSONArray()
            WidgetBoard(
                checkedAtMs = board.optLongOrNull("checkedAtMs"),
                failedAtMs = board.optLongOrNull("failedAtMs"),
                arrivals = (0 until arrivals.length()).mapNotNull { i ->
                    val a = arrivals.optJSONObject(i) ?: return@mapNotNull null
                    val line = a.optString("line", "")
                    val due = a.optLongOrNull("dueMs")
                    if (line.isEmpty() || due == null) null
                    else WidgetArrival(
                        line = line,
                        destination = a.optString("dest", "Línea $line"),
                        clock = a.optString("clock", ""),
                        dueMs = due,
                        accessible = a.optBoolean("acc", false),
                    )
                },
            )
        } catch (e: Exception) {
            null
        }
    }

    /** The ids kept for a widget (`widget_{id}_stops`), "574,3140". */
    fun parseIds(value: String?): List<Int> =
        value.orEmpty().split(',').mapNotNull { it.trim().toIntOrNull() }

    /**
     * The [count] stops a widget shows: the ones it [chose] that are still
     * saved, then the first saved ones, never twice.
     */
    fun pickStops(saved: List<SavedStop>, chose: List<Int>, count: Int): List<SavedStop> {
        val picked = mutableListOf<SavedStop>()
        for (id in chose) {
            val stop = saved.firstOrNull { it.id == id } ?: continue
            if (picked.size < count && picked.none { it.id == id }) picked += stop
        }
        for (stop in saved) {
            if (picked.size >= count) break
            if (picked.none { it.id == stop.id }) picked += stop
        }
        return picked
    }

    /**
     * The stops after a tap on slot [slot]: that slot moves to the next
     * saved stop the widget does not show yet, in the order of Mis paradas.
     */
    fun nextStop(saved: List<SavedStop>, shown: List<SavedStop>, slot: Int): List<SavedStop> {
        if (slot !in shown.indices || saved.size <= shown.size) return shown
        val start = saved.indexOfFirst { it.id == shown[slot].id }
        for (step in 1..saved.size) {
            val candidate = saved[(start + step) % saved.size]
            if (shown.none { it.id == candidate.id }) {
                return shown.toMutableList().also { it[slot] = candidate }
            }
        }
        return shown
    }

    /** The buses still to come at [nowMs], soonest first. */
    fun upcoming(board: WidgetBoard?, nowMs: Long): List<WidgetArrival> =
        board?.arrivals
            ?.filter { nowMs <= it.dueMs + EXPIRED_AFTER_MS }
            ?.sortedBy { it.dueMs }
            .orEmpty()

    /** True if an empty board should ask for a refresh, not say "no buses". */
    fun isStale(board: WidgetBoard?, nowMs: Long): Boolean {
        val checked = board?.checkedAtMs ?: return true
        return nowMs - checked > STALE_AFTER_MS
    }

    /**
     * The footer for [boards] (the stops a widget shows): refreshing for
     * 30 s after a tap, failed if any stop failed, else when the oldest
     * stop was checked.
     */
    fun footer(boards: List<WidgetBoard?>, refreshTapMs: Long?, nowMs: Long): WidgetFooter {
        val checked = boards.map { it?.checkedAtMs }
        if (refreshTapMs != null && nowMs - refreshTapMs in 0 until REFRESHING_FOR_MS &&
            checked.any { it == null || it < refreshTapMs } &&
            boards.none { it?.failedAtMs != null && it.failedAtMs >= refreshTapMs }
        ) {
            return WidgetFooter.Refreshing
        }
        val known = checked.filterNotNull()
        if (boards.any { it?.failed == true }) return WidgetFooter.Failed(known.minOrNull())
        if (known.isEmpty()) return WidgetFooter.NoData
        return WidgetFooter.Checked(known.min())
    }

    /**
     * When the widget has to be drawn again with no new data: the next bus
     * to drop out of [shown], the end of "Actualizando…", or an empty board
     * turning stale. Null if nothing changes on its own.
     */
    fun nextRedrawMs(
        shown: List<WidgetArrival>,
        boards: List<WidgetBoard?>,
        refreshTapMs: Long?,
        nowMs: Long,
    ): Long? {
        val times = mutableListOf<Long>()
        shown.mapTo(times) { it.dueMs + EXPIRED_AFTER_MS + 1 }
        if (refreshTapMs != null) times += refreshTapMs + REFRESHING_FOR_MS + 1
        boards.forEach { board -> board?.checkedAtMs?.let { times += it + STALE_AFTER_MS + 1 } }
        return times.filter { it > nowMs }.minOrNull()
    }

    private fun JSONObject.optLongOrNull(key: String): Long? =
        if (has(key) && !isNull(key)) optLong(key) else null
}
