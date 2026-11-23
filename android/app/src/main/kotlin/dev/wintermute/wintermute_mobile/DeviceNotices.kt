package dev.wintermute.wintermute_mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

internal object DeviceNotices {
    const val CHANNEL = "dev.wintermute/user_notifications"
    const val OPEN = "dev.wintermute.OPEN_NOTICE"
    private const val USER_CHANNEL = "agent_reminders"
    private const val JOB = 58210
    var foreground = false

    fun enabled(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    USER_CHANNEL,
                    "Agent 消息提醒",
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
            if (
                manager.getNotificationChannel(USER_CHANNEL).importance ==
                    NotificationManager.IMPORTANCE_NONE
            )
                return false
        }
        return manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED)
    }

    fun schedule(context: Context, enabled: Boolean) {
        val jobs = context.getSystemService(JobScheduler::class.java)
        if (!enabled) {
            jobs.cancel(JOB)
            return
        }
        if (jobs.allPendingJobs.none { it.id == JOB }) {
            jobs.schedule(
                JobInfo.Builder(JOB, ComponentName(context, NoticeJobService::class.java))
                    .setPeriodic(15 * 60_000L)
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .setPersisted(true)
                    .build()
            )
        }
    }

    private fun tag(scope: String, id: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest((scope + "\u0000" + id).toByteArray())
            .joinToString("") { "%02x".format(it) }

    // Both engines run on this process's main thread. Keep a small receipt cache
    // so a lost HTTP acknowledgement doesn't alert twice on the next poll.
    fun present(
        context: Context,
        scope: String,
        id: String,
        title: String,
        body: String?,
        inApp: Boolean = false,
    ): Boolean {
        val key = tag(scope, id)
        val prefs = context.getSharedPreferences("notice_receipts", Context.MODE_PRIVATE)
        if (prefs.contains(key)) return true
        if (foreground != inApp) return false
        if (enabled(context)) {
            val launch =
                Intent(context, MainActivity::class.java)
                    .setAction(OPEN)
                    .setData(android.net.Uri.parse("wintermute://notification/" + key))
                    .putExtra("scope", scope)
                    .putExtra("id", id)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val intent =
                PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            val notification =
                NotificationCompat.Builder(context, USER_CHANNEL)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setOnlyAlertOnce(true)
                    .setAutoCancel(true)
                    .setContentIntent(intent)
                    .build()
            context.getSystemService(NotificationManager::class.java).notify(key, 1, notification)
        } else if (!inApp) return false
        val edit = prefs.edit().putLong(key, System.currentTimeMillis())
        if (prefs.all.size >= 512) {
            prefs.all.entries
                .sortedBy { it.value as? Long ?: 0L }
                .take(128)
                .forEach { edit.remove(it.key) }
        }
        edit.apply()
        return true
    }

    fun dismiss(context: Context, scope: String, id: String) =
        context.getSystemService(NotificationManager::class.java).cancel(tag(scope, id), 1)
}

class NoticeJobService : JobService() {
    private var engine: FlutterEngine? = null
    private var current: JobParameters? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onStartJob(params: JobParameters): Boolean {
        if (DeviceNotices.foreground || !DeviceNotices.enabled(this)) return false
        current = params
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationCompleteAsync(applicationContext, null, main) {
            if (current !== params) return@ensureInitializationCompleteAsync
            try {
                val runtime = FlutterEngine(applicationContext)
                engine = runtime
                MethodChannel(runtime.dartExecutor.binaryMessenger, DeviceNotices.CHANNEL)
                    .setMethodCallHandler { call, result ->
                        when (call.method) {
                            "post" ->
                                try {
                                    result.success(
                                        DeviceNotices.present(
                                            this,
                                            call.argument<String>("scope")!!,
                                            call.argument<String>("id")!!,
                                            call.argument<String>("title")!!,
                                            call.argument<String>("body"),
                                        )
                                    )
                                } catch (error: Exception) {
                                    result.error("notice", error.message, null)
                                }
                            "finished" -> {
                                val retry = call.argument<Boolean>("retry") == true
                                result.success(null)
                                main.post {
                                    if (current === params) {
                                        stopEngine()
                                        jobFinished(params, retry)
                                    }
                                }
                            }
                            else -> result.notImplemented()
                        }
                    }
                runtime.dartExecutor.executeDartEntrypoint(
                    DartEntrypoint(loader.findAppBundlePath(), "notificationJob")
                )
            } catch (_: RuntimeException) {
                stopEngine()
                jobFinished(params, true)
            }
        }
        return true
    }

    private fun stopEngine() {
        current = null
        engine?.destroy()
        engine = null
    }

    override fun onStopJob(params: JobParameters): Boolean {
        stopEngine()
        return true
    }

    override fun onDestroy() {
        stopEngine()
        super.onDestroy()
    }
}
