package com.liberontech.stmapp

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class MVDTransporteWidgetProvider : AppWidgetProvider() {

    companion object {
        // Same pages as OfficialSite in lib/services/official_sites.dart
        private const val MI_STM_URL =
            "https://stm.gub.uy/app/mistm/cuenta/pages/principal.xhtml"
        private const val RECARGA_URL =
            "https://stm.gub.uy/app/mistm/cuenta/recargaRapida.xhtml"

        // The row is hidden this long after its bus was due
        private const val EXPIRED_AFTER_MS = 2 * 60 * 1000L
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)

        val views = RemoteViews(context.packageName, R.layout.mvd_transporte_widget)

        // Buttons open the official site in the browser. There is no card
        // balance here any more: the app no longer embeds Mi STM in a
        // WebView, so it cannot read the balance from the page.
        views.setOnClickPendingIntent(
            R.id.widget_btn_mistm,
            browserIntent(context, 0, MI_STM_URL)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_recarga,
            browserIntent(context, 1, RECARGA_URL)
        )

        // Route ETA row (saved by the background alert check)
        val routeLine = widgetData.getString("route_line", null)
        val routeEtaMin = widgetData.getInt("route_eta_min", -1)
        val routeDest = widgetData.getString("route_dest", null)
        // Absolute time stays correct between background refreshes (≥15 min)
        val routeEtaAt = widgetData.getString("route_eta_at", null)
        // When the bus is due, on the phone's clock (ms since epoch, as
        // text): a row the app could not refresh must not show a bus that
        // has passed
        val routeExpectedAtMs =
            widgetData.getString("route_expected_at_ms", null)?.toLongOrNull()
        val expired = routeExpectedAtMs != null &&
            System.currentTimeMillis() > routeExpectedAtMs + EXPIRED_AFTER_MS

        if (!expired && routeLine != null && routeEtaMin >= 0 && routeDest != null) {
            val etaLabel = when {
                routeEtaAt != null -> "~$routeEtaAt"
                routeEtaMin == 0 -> "ahora"
                else -> "$routeEtaMin min"
            }
            val spokenEta = when {
                routeEtaAt != null -> "alrededor de las $routeEtaAt"
                routeEtaMin == 0 -> "ahora"
                else -> "en unos $routeEtaMin minutos"
            }
            views.setTextViewText(R.id.widget_route_line, routeLine)
            views.setTextViewText(R.id.widget_route_dest, routeDest)
            views.setTextViewText(R.id.widget_route_eta, etaLabel)
            // TalkBack reads the row as one sentence, not "116", "POCITOS"
            views.setContentDescription(
                R.id.widget_route_section,
                "Línea $routeLine a $routeDest, $spokenEta, estimado"
            )
            views.setViewVisibility(R.id.widget_route_section, View.VISIBLE)
            views.setViewVisibility(R.id.widget_route_empty, View.GONE)
        } else {
            // No enabled route alert, none of its lines is coming, or the
            // bus shown last has passed
            views.setViewVisibility(R.id.widget_route_section, View.GONE)
            views.setViewVisibility(R.id.widget_route_empty, View.VISIBLE)
        }

        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun browserIntent(context: Context, requestCode: Int, url: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            Intent(Intent.ACTION_VIEW, Uri.parse(url)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
}
