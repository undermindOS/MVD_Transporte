package com.liberontech.stmapp

import android.content.Context
import android.os.Build
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import es.antonborri.home_widget.HomeWidgetPlugin
import java.util.concurrent.TimeUnit

/** Both refresh paths run the same Dart task, with a lifetime owned by WorkManager.
 * No activity, app unlock, Hive box or JobIntentService is needed to refresh. */
object StopWidgetWork {
    const val TASK = "stopWidgetRefresh"
    const val PERIODIC = "stop-widget-periodic"
    const val MANUAL = "stop-widget-manual"
    const val KEY_MINUTES = "widget_refresh_minutes"
    private val input = Data.Builder().putString(BackgroundWorker.DART_TASK_KEY, TASK).build()

    fun refresh(context: Context) {
        val request = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
            .setInputData(input)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .apply {
                // Before Android 12 expedited work needs a foreground service;
                // the Dart worker has no foreground notification of its own.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                }
            }
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(MANUAL, ExistingWorkPolicy.KEEP, request)
    }

    fun sync(context: Context, placed: Int) {
        val data = HomeWidgetPlugin.getData(context)
        val minutes = data.getInt(KEY_MINUTES, 15).takeIf { it in listOf(0, 15, 30, 60) } ?: 15
        val manager = WorkManager.getInstance(context)
        if (placed == 0 || minutes == 0) {
            manager.cancelUniqueWork(PERIODIC)
            return
        }
        val request = PeriodicWorkRequest.Builder(
            BackgroundWorker::class.java, minutes.toLong(), TimeUnit.MINUTES)
            .setInputData(input)
            .setInitialDelay(minutes.toLong(), TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        // UPDATE applies changed intervals without cancelling a running refresh.
        manager.enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.UPDATE, request)
    }
}
