package com.example.stm_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class MVDTransporteWidgetProvider : AppWidgetProvider() {

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

        val balance = widgetData.getString("card_balance", null)
        val updated = widgetData.getString("balance_updated", null)

        val views = RemoteViews(context.packageName, R.layout.mvd_transporte_widget)

        // Set balance text
        views.setTextViewText(
            R.id.widget_balance,
            balance ?: "Sin datos"
        )

        // Set timestamp
        if (updated != null) {
            views.setTextViewText(R.id.widget_updated, "Actualizado: $updated")
        }

        // "Inicio" button — opens app at tab 0
        val inicioIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("tab", 0)
        }
        val inicioPending = PendingIntent.getActivity(
            context, 0, inicioIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_btn_inicio, inicioPending)

        // "Recarga" button — opens app at tab 1
        val recargaIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("tab", 1)
        }
        val recargaPending = PendingIntent.getActivity(
            context, 1, recargaIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_btn_recarga, recargaPending)

        // Route ETA row (visible only when a route ETA has been saved)
        val routeLine = widgetData.getString("route_line", null)
        val routeEtaMin = widgetData.getInt("route_eta_min", -1)
        val routeDest = widgetData.getString("route_dest", null)

        if (routeLine != null && routeEtaMin >= 0 && routeDest != null) {
            views.setViewVisibility(R.id.widget_route_section, View.VISIBLE)
            val etaLabel = if (routeEtaMin == 0) "ahora" else "$routeEtaMin min"
            views.setTextViewText(
                R.id.widget_route_text,
                "$routeLine → $routeDest: $etaLabel"
            )
        } else {
            views.setViewVisibility(R.id.widget_route_section, View.GONE)
        }

        appWidgetManager.updateAppWidget(widgetId, views)
    }
}
