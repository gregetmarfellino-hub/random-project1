package com.example.pyclean_mobile 

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

class PycleanWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                // INI KABEL GHAIBNYA: Nyambungin tombol ke Flutter Background Task
                val pendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("pyclean://execute_clean")
                )
                setOnClickPendingIntent(R.id.btn_clean, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}