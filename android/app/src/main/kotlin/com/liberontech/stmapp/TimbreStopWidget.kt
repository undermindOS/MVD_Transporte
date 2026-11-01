package com.liberontech.stmapp

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The stop widgets: Próximo (2 × 2), Parada (4 × 2) and Mis paradas (4 × 4)
 * (docs/design/10-superficies.md). They read what StopWidgetsFeed writes
 * (lib/services/stop_widgets_feed.dart); the rules live in StopWidgetData.
 *
 * - Tapping the stop name shows the next saved stop, per widget.
 * - The refresh button enqueues a WorkManager task, without opening the app.
 * - Last successful arrivals stay visible with their original clock times.
 * - WorkManager updates them at the interval selected in the app.
 */
abstract class TimbreStopWidget : AppWidgetProvider() {

    /** The layout this widget draws, and how many stops it shows. */
    protected abstract val layoutId: Int
    protected abstract val stopCount: Int

    /**
     * Fills [views] for [stops] (never empty) and their [boards], at [nowMs].
     * Returns the buses on screen, so the widget is redrawn when one drops.
     */
    protected abstract fun fill(
        context: Context,
        views: RemoteViews,
        widgetId: Int,
        saved: List<SavedStop>,
        stops: List<SavedStop>,
        boards: List<WidgetBoard?>,
        footer: WidgetFooter,
        nowMs: Long,
    ): List<WidgetArrival>

    /** No saved stops: what else to hide besides the board (w_empty shows). */
    protected open fun drawNoStops(views: RemoteViews) {}

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        drawAll(context)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = widgetPrefs(context).edit()
        ids.forEach { edit.remove(keyChosen(it)) }
        edit.apply()
        publishShown(context, deleted = ids.toSet())
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_NEXT_STOP -> {
                val parts = intent.data?.pathSegments.orEmpty()
                val widgetId = parts.getOrNull(0)?.toIntOrNull() ?: return
                val slot = parts.getOrNull(1)?.toIntOrNull() ?: return
                showNextStop(context, widgetId, slot)
                drawAll(context)
            }
            ACTION_REFRESH -> {
                widgetPrefs(context).edit()
                    .putLong(KEY_REFRESH_TAP, System.currentTimeMillis()).apply()
                askForData(context)
                redrawEveryWidget(context)
            }
            else -> super.onReceive(context, intent)
        }
    }

    /** Draws every widget of this kind and plans the next redraw. */
    private fun drawAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
        val data = HomeWidgetPlugin.getData(context)
        val saved = StopWidgetData.parseStops(data.getString(KEY_SAVED_STOPS, null))
        val tap = widgetPrefs(context).getLong(KEY_REFRESH_TAP, 0L).takeIf { it > 0 }
        val now = System.currentTimeMillis()
        var nextRedraw: Long? = null
        var missingBoard = false

        for (id in ids) {
            val views = RemoteViews(context.packageName, layoutId)
            views.setOnClickPendingIntent(android.R.id.background, openApp(context))
            if (saved.isEmpty()) {
                views.setViewVisibility(R.id.w_board, View.GONE)
                views.setViewVisibility(R.id.w_empty, View.VISIBLE)
                drawNoStops(views)
                manager.updateAppWidget(id, views)
                continue
            }
            views.setViewVisibility(R.id.w_board, View.VISIBLE)
            views.setViewVisibility(R.id.w_empty, View.GONE)
            views.setOnClickPendingIntent(R.id.w_refresh, refreshIntent(context))

            val stops = chosenStops(context, id, saved)
            val boards = stops.map { boardOf(data, it.id) }
            if (boards.any { it == null }) missingBoard = true
            val footer = StopWidgetData.footer(boards, tap, now)
            fill(context, views, id, saved, stops, boards, footer, now)
            manager.updateAppWidget(id, views)

            StopWidgetData.nextRedrawMs(boards, tap, now)?.let {
                nextRedraw = minOf(nextRedraw ?: it, it)
            }
        }
        planRedraw(context, ids, nextRedraw)
        publishShown(context)
        // A stop never fetched (just placed, or switched to): ask once
        if (missingBoard) askForData(context)
    }

    private fun chosenStops(context: Context, widgetId: Int, saved: List<SavedStop>): List<SavedStop> {
        val chose = StopWidgetData.parseIds(widgetPrefs(context).getString(keyChosen(widgetId), null))
        return StopWidgetData.pickStops(saved, chose, stopCount)
    }

    private fun showNextStop(context: Context, widgetId: Int, slot: Int) {
        val saved = StopWidgetData.parseStops(
            HomeWidgetPlugin.getData(context).getString(KEY_SAVED_STOPS, null))
        val shown = chosenStops(context, widgetId, saved)
        val next = StopWidgetData.nextStop(saved, shown, slot)
        widgetPrefs(context).edit()
            .putString(keyChosen(widgetId), next.joinToString(",") { it.id.toString() })
            .apply()
    }

    /** Redraws this kind when its next bus drops out (inexact: no wakeup). */
    private fun planRedraw(context: Context, ids: IntArray, atMs: Long?) {
        val intent = Intent(context, javaClass)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        val pending = PendingIntent.getBroadcast(
            context, REQUEST_REDRAW, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        if (atMs == null || ids.isEmpty()) alarms.cancel(pending)
        else alarms.set(AlarmManager.RTC, atMs, pending)
    }

    // ---------------------------------------------------------- drawing ---

    protected fun header(
        context: Context,
        views: RemoteViews,
        widgetId: Int,
        saved: List<SavedStop>,
        stop: SavedStop,
        slot: Int,
        headerId: Int,
        nameId: Int,
        withNumber: Boolean = true,
    ) {
        val text = SpannableStringBuilder(stop.name)
        if (withNumber) {
            // " · 574", smaller and dimmer than the name
            val start = text.length
            text.append(" · ${stop.id}")
            text.setSpan(ForegroundColorSpan(context.getColor(R.color.etiqueta)),
                start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            text.setSpan(RelativeSizeSpan(0.82f), start, text.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        views.setTextViewText(nameId, text)
        if (saved.size > stopCount) {
            views.setOnClickPendingIntent(headerId, nextStopIntent(context, widgetId, slot))
            views.setContentDescription(headerId,
                "Parada ${stop.name}, ${stop.id}. Tocá para ver otra parada")
        } else {
            views.setOnClickPendingIntent(headerId, openApp(context))
            views.setContentDescription(headerId, "Parada ${stop.name}, ${stop.id}")
        }
    }

    /** One widget_stop_row per bus of [buses], in [rowsId]. */
    protected fun rows(context: Context, views: RemoteViews, rowsId: Int, buses: List<WidgetArrival>) {
        views.removeAllViews(rowsId)
        buses.forEachIndexed { i, bus ->
            val row = RemoteViews(context.packageName, R.layout.widget_stop_row)
            row.setViewVisibility(R.id.w_row_divider, if (i == 0) View.GONE else View.VISIBLE)
            row.setTextViewText(R.id.w_row_line, bus.line)
            row.setTextViewText(R.id.w_row_dest, bus.destination)
            row.setViewVisibility(R.id.w_row_acc, if (bus.accessible) View.VISIBLE else View.GONE)
            row.setTextViewText(R.id.w_row_time, "~${bus.clock}")
            row.setContentDescription(R.id.w_row, spoken(bus))
            views.addView(rowsId, row)
        }
    }

    /** "Sin próximos ómnibus…" or, for an old board, a refresh. */
    protected fun message(context: Context, views: RemoteViews, messageId: Int, board: WidgetBoard?, nowMs: Long) {
        views.setViewVisibility(messageId, View.VISIBLE)
        if (StopWidgetData.isStale(board, nowMs)) {
            views.setTextViewText(messageId, if (board?.checkedAtMs == null) "Sin datos todavía. Tocá para actualizar"
                else "Sin ómnibus en la última consulta. Tocá para actualizar")
            views.setOnClickPendingIntent(messageId, refreshIntent(context))
        } else {
            views.setTextViewText(messageId, "Sin próximos ómnibus en esta parada")
            views.setOnClickPendingIntent(messageId, openApp(context))
        }
    }

    protected fun footer(context: Context, views: RemoteViews, footer: WidgetFooter, suffix: String = "") {
        val (text, failed) = when (footer) {
            is WidgetFooter.Checked -> "Datos de las ${clock(footer.atMs)}$suffix" to false
            is WidgetFooter.Saved -> "Últimos datos\n${snapshotClock(footer.atMs)}" to false
            is WidgetFooter.Failed -> (footer.atMs?.let {
                "No se pudo actualizar. Datos de las ${clock(it)}."
            } ?: "No se pudo actualizar.") to true
            WidgetFooter.Refreshing -> "Actualizando…" to false
            WidgetFooter.NoData -> "Tocá para actualizar" to false
        }
        views.setTextViewText(R.id.w_footer, text)
        views.setOnClickPendingIntent(R.id.w_footer, refreshIntent(context))
        views.setContentDescription(R.id.w_footer, "$text. Tocá para actualizar")
        views.setTextColor(R.id.w_footer,
            context.getColor(if (failed) R.color.rojo_led else R.color.tenue))
        views.setViewVisibility(R.id.w_footer_icon, if (failed) View.VISIBLE else View.GONE)
    }

    companion object {
        private const val ACTION_NEXT_STOP = "com.liberontech.stmapp.widget.NEXT_STOP"
        private const val ACTION_REFRESH = "com.liberontech.stmapp.widget.REFRESH"
        private const val REQUEST_REDRAW = 1

        // Written by the app (StopWidgetsFeed in lib/services/stop_widgets_feed.dart)
        const val KEY_SAVED_STOPS = "stops_saved"
        private const val BOARD_PREFIX = "stop_board_"

        // Written here, read by the app
        const val KEY_SHOWN_STOPS = "stops_shown"
        const val KEY_PLACED = "stop_widgets_placed"

        // The widgets' own state
        private const val WIDGET_PREFS = "timbre_stop_widgets"
        private const val KEY_REFRESH_TAP = "refresh_tap_ms"
        private const val KEY_REFRESH_ASKED = "refresh_asked_ms"
        private fun keyChosen(widgetId: Int) = "widget_${widgetId}_stops"

        private val KINDS = listOf(
            TimbreProximoWidget::class.java to 1,
            TimbreParadaWidget::class.java to 1,
            TimbreMisParadasWidget::class.java to 2,
            TimbreAnchoWidget::class.java to 1,
            TimbreFlipWidget::class.java to 1,
        )

        private fun widgetPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)

        private fun boardOf(data: SharedPreferences, stopId: Int): WidgetBoard? =
            StopWidgetData.parseBoard(data.getString("$BOARD_PREFIX$stopId", null))

        /**
         * Writes which stops the placed widgets show, and how many there
         * are: the app fetches those in the background and keeps its
         * periodic check while any is placed.
         */
        private fun publishShown(context: Context, deleted: Set<Int> = emptySet()) {
            val manager = AppWidgetManager.getInstance(context)
            val data = HomeWidgetPlugin.getData(context)
            val saved = StopWidgetData.parseStops(data.getString(KEY_SAVED_STOPS, null))
            val shown = linkedSetOf<Int>()
            var placed = 0
            for ((kind, count) in KINDS) {
                for (id in manager.getAppWidgetIds(ComponentName(context, kind))) {
                    if (id in deleted) continue
                    placed++
                    val chose = StopWidgetData.parseIds(widgetPrefs(context).getString(keyChosen(id), null))
                    StopWidgetData.pickStops(saved, chose, count).mapTo(shown) { it.id }
                }
            }
            StopWidgetWork.sync(context, placed)
            val shownText = shown.joinToString(",")
            if (data.getString(KEY_SHOWN_STOPS, null) != shownText ||
                data.getString(KEY_PLACED, null) != placed.toString()
            ) {
                data.edit()
                    .putString(KEY_SHOWN_STOPS, shownText)
                    .putString(KEY_PLACED, placed.toString())
                    .apply()
            }
        }

        /**
         * Asks the app's Dart code for new boards of the shown stops, at most
         * once every 15 s. Runs without opening the app.
         */
        private fun askForData(context: Context) {
            val prefs = widgetPrefs(context)
            val now = System.currentTimeMillis()
            val last = prefs.getLong(KEY_REFRESH_ASKED, 0L)
            if (now - last in 0 until StopWidgetData.REFRESH_GAP_MS) return
            prefs.edit().putLong(KEY_REFRESH_ASKED, now).apply()
            StopWidgetWork.refresh(context)
        }

        private fun redrawEveryWidget(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for ((kind, _) in KINDS) {
                val ids = manager.getAppWidgetIds(ComponentName(context, kind))
                if (ids.isEmpty()) continue
                context.sendBroadcast(
                    Intent(context, kind)
                        .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids))
            }
        }

        private fun openApp(context: Context): PendingIntent {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            return PendingIntent.getActivity(context, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        /** A time on the phone's clock, "H:MM" as in the app. */
        fun clock(ms: Long): String = SimpleDateFormat("H:mm", Locale.US).format(Date(ms))
        private fun snapshotClock(ms: Long): String =
            SimpleDateFormat("dd/MM H:mm", Locale.US).format(Date(ms))

        /** TalkBack reads a row as one sentence. */
        fun spoken(bus: WidgetArrival): String =
            "Línea ${bus.line} a ${bus.destination}, alrededor de las ${bus.clock}, estimado" +
                if (bus.accessible) ", accesible" else ""
    }

    private fun refreshIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(context, 0,
            Intent(context, javaClass).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** The data makes each widget and slot its own PendingIntent. */
    private fun nextStopIntent(context: Context, widgetId: Int, slot: Int): PendingIntent =
        PendingIntent.getBroadcast(context, 0,
            Intent(context, javaClass)
                .setAction(ACTION_NEXT_STOP)
                .setData(Uri.parse("timbre://widget/$widgetId/$slot")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** Opens an official site in the browser (Mis paradas' links). */
    protected fun browserIntent(context: Context, requestCode: Int, url: String): PendingIntent =
        PendingIntent.getActivity(context, requestCode,
            Intent(Intent.ACTION_VIEW, Uri.parse(url)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
}

/**
 * Próximo (2 × 2): a clock, then one stop, its next bus and the two after it.
 * The clock is a TextClock in the layout and keeps itself current. Its LED
 * look is a mask over the system font: a widget cannot use the app's fonts.
 */
open class TimbreProximoWidget : TimbreStopWidget() {
    override val layoutId = R.layout.widget_stop_small
    override val stopCount = 1
    protected open val compactWidth = true

    override fun fill(
        context: Context, views: RemoteViews, widgetId: Int, saved: List<SavedStop>,
        stops: List<SavedStop>, boards: List<WidgetBoard?>, footer: WidgetFooter, nowMs: Long,
    ): List<WidgetArrival> {
        val stop = stops.first()
        views.setViewVisibility(R.id.w_header, View.VISIBLE)
        // Small: the name alone, the number would push it out
        header(context, views, widgetId, saved, stop, 0, R.id.w_header, R.id.w_stop_name,
            withNumber = !compactWidth)
        val buses = StopWidgetData.snapshot(boards[0]).take(
            // Give a long full stop name room in a compact 2 x 2 widget.
            if (compactWidth && stop.name.length > 42) 1 else 3)
        val next = buses.firstOrNull()
        val busViews = listOf(R.id.w_next_bus, R.id.w_after)
        if (next == null) {
            busViews.forEach { views.setViewVisibility(it, View.GONE) }
            views.setViewVisibility(R.id.w_spacer, View.GONE)
            message(context, views, R.id.w_message, boards[0], nowMs)
        } else {
            busViews.forEach { views.setViewVisibility(it, View.VISIBLE) }
            views.setViewVisibility(R.id.w_spacer, View.VISIBLE)
            views.setViewVisibility(R.id.w_message, View.GONE)
            views.setTextViewText(R.id.w_line, next.line)
            views.setTextViewText(R.id.w_dest, next.destination)
            views.setViewVisibility(R.id.w_acc, if (next.accessible) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.w_time, "~${next.clock}")
            views.setContentDescription(R.id.w_next_bus, spoken(next))
            val after = SpannableStringBuilder()
            buses.drop(1).forEachIndexed { i, bus ->
                if (i > 0) after.append(" · ")
                val start = after.length
                after.append(bus.line)
                after.setSpan(ForegroundColorSpan(context.getColor(R.color.ambar)),
                    start, after.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                after.append(" ~${bus.clock}")
            }
            views.setTextViewText(R.id.w_after, after)
            views.setViewVisibility(R.id.w_after, if (after.isEmpty()) View.GONE else View.VISIBLE)
            views.setContentDescription(R.id.w_after,
                buses.drop(1).joinToString(". ") { spoken(it) })
        }
        footer(context, views, footer)
        return buses
    }
}

/** Parada (4 × 2): one stop and its next three buses. */
open class TimbreParadaWidget : TimbreStopWidget() {
    override val layoutId = R.layout.widget_stop_medium
    override val stopCount = 1
    protected open val rowCount = 3

    override fun fill(
        context: Context, views: RemoteViews, widgetId: Int, saved: List<SavedStop>,
        stops: List<SavedStop>, boards: List<WidgetBoard?>, footer: WidgetFooter, nowMs: Long,
    ): List<WidgetArrival> {
        header(context, views, widgetId, saved, stops.first(), 0, R.id.w_header, R.id.w_stop_name)
        val buses = StopWidgetData.snapshot(boards[0]).take(rowCount)
        rows(context, views, R.id.w_rows, buses)
        if (buses.isEmpty()) {
            views.setViewVisibility(R.id.w_spacer, View.GONE)
            message(context, views, R.id.w_message, boards[0], nowMs)
        } else {
            views.setViewVisibility(R.id.w_spacer, View.VISIBLE)
            views.setViewVisibility(R.id.w_message, View.GONE)
        }
        footer(context, views, footer, " · horas estimadas")
        return buses
    }
}

/**
 * Próximo across the whole four-column grid: a larger clock, with the day
 * and the stop beside it, so the stop's header sits outside the board.
 */
class TimbreAnchoWidget : TimbreProximoWidget() {
    override val layoutId = R.layout.widget_stop_wide
    override val compactWidth = false

    override fun drawNoStops(views: RemoteViews) {
        views.setViewVisibility(R.id.w_header, View.GONE)
    }
}

/** Samsung Flex Window, registered separately for the cover-screen picker. */
class TimbreFlipWidget : TimbreParadaWidget() {
    override val layoutId = R.layout.widget_stop_cover
    override val rowCount = 6
}

/** Mis paradas (4 × 4): two stops, three buses each, Mi STM and Recarga. */
class TimbreMisParadasWidget : TimbreStopWidget() {
    override val layoutId = R.layout.widget_stop_large
    override val stopCount = 2

    override fun fill(
        context: Context, views: RemoteViews, widgetId: Int, saved: List<SavedStop>,
        stops: List<SavedStop>, boards: List<WidgetBoard?>, footer: WidgetFooter, nowMs: Long,
    ): List<WidgetArrival> {
        // Same pages as OfficialSite in lib/services/official_sites.dart
        views.setOnClickPendingIntent(R.id.w_btn_mistm, browserIntent(context, 10,
            "https://stm.gub.uy/app/mistm/cuenta/pages/principal.xhtml"))
        views.setOnClickPendingIntent(R.id.w_btn_recarga, browserIntent(context, 11,
            "https://stm.gub.uy/app/mistm/cuenta/recargaRapida.xhtml"))

        val sections = listOf(
            Section(R.id.w_section_1, R.id.w_header_1, R.id.w_stop_name_1, R.id.w_rows_1, R.id.w_message_1),
            Section(R.id.w_section_2, R.id.w_header_2, R.id.w_stop_name_2, R.id.w_rows_2, R.id.w_message_2),
        )
        val shown = mutableListOf<WidgetArrival>()
        sections.forEachIndexed { slot, section ->
            val stop = stops.getOrNull(slot)
            if (stop == null) {
                // One saved stop: the second section and the line go away
                views.setViewVisibility(section.root, View.GONE)
                views.setViewVisibility(R.id.w_divider, View.GONE)
                return@forEachIndexed
            }
            views.setViewVisibility(section.root, View.VISIBLE)
            if (slot == 1) views.setViewVisibility(R.id.w_divider, View.VISIBLE)
            header(context, views, widgetId, saved, stop, slot, section.header, section.name)
            val buses = StopWidgetData.snapshot(boards[slot]).take(3)
            rows(context, views, section.rows, buses)
            if (buses.isEmpty()) message(context, views, section.message, boards[slot], nowMs)
            else views.setViewVisibility(section.message, View.GONE)
            shown += buses
        }
        footer(context, views, footer)
        return shown
    }

    private data class Section(val root: Int, val header: Int, val name: Int, val rows: Int, val message: Int)
}
