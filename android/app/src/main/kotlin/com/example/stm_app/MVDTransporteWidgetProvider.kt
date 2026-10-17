package com.example.stm_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
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

        // Buttons open a tab; Flutter reads the URI via HomeWidget
        // (a plain "tab" extra was never read by the Dart side)
        // "Inicio" button — opens app at tab 0
        views.setOnClickPendingIntent(
            R.id.widget_btn_inicio,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java,
                Uri.parse("mvdtransporte://tab?index=0")
            )
        )

        // "Recarga" button — opens app at tab 1
        views.setOnClickPendingIntent(
            R.id.widget_btn_recarga,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java,
                Uri.parse("mvdtransporte://tab?index=1")
            )
        )

        // Route ETA row (visible only when a route ETA has been saved)
        val routeLine = widgetData.getString("route_line", null)
        val routeEtaMin = widgetData.getInt("route_eta_min", -1)
        val routeDest = widgetData.getString("route_dest", null)
        // Absolute time stays correct between background refreshes (≥15 min)
        val routeEtaAt = widgetData.getString("route_eta_at", null)

        if (routeLine != null && routeEtaMin >= 0 && routeDest != null) {
            views.setViewVisibility(R.id.widget_route_section, View.VISIBLE)
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
            views.setViewVisibility(R.id.widget_route_section, View.GONE)
        }

        appWidgetManager.updateAppWidget(widgetId, views)
    }
}
