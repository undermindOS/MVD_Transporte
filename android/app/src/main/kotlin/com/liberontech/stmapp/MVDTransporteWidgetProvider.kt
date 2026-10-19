package com.liberontech.stmapp

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class MVDTransporteWidgetProvider : AppWidgetProvider() {

    companion object {
        // Same pages as OfficialSite in lib/services/official_sites.dart
        private const val MI_STM_URL =
            "https://stm.gub.uy/app/mistm/cuenta/pages/principal.xhtml"
        private const val RECARGA_URL =
            "https://stm.gub.uy/app/mistm/cuenta/recargaRapida.xhtml"
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

        if (routeLine != null && routeEtaMin >= 0 && routeDest != null) {
            val etaLabel = when {
                routeEtaAt != null -> "~$routeEtaAt"
                routeEtaMin == 0 -> "ahora"
                else -> "$routeEtaMin min"
            }
            views.setTextViewText(
                R.id.widget_route_text,
                "$routeLine → $routeDest: $etaLabel"
            )
        } else {
            // No enabled route alert, or none of its lines is coming
            views.setTextViewText(R.id.widget_route_text, "Sin próximos ómnibus en tus rutas")
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
