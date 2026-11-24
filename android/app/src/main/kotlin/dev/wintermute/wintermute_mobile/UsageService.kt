package dev.wintermute.wintermute_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Owns completed external-app records independently of the Activity lifecycle. */
class UsageService : Service() {
    private val signals by lazy { MobileSignals.get(this) }
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    @Volatile private var active = false

    override fun onCreate() {
        super.onCreate()
        if (!promote()) {
            stopSelf()
            return
        }
        active = true
        running = true
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationCompleteAsync(applicationContext, null, main) {
            if (!active) return@ensureInitializationCompleteAsync
            try {
                val runtime = FlutterEngine(applicationContext)
                engine = runtime
                MethodChannel(runtime.dartExecutor.binaryMessenger, "dev.wintermute/usage_worker")
                    .setMethodCallHandler(::handle)
                runtime.dartExecutor.executeDartEntrypoint(DartEntrypoint(loader.findAppBundlePath(), "usageWorker"))
            } catch (e: RuntimeException) {
                android.util.Log.w("WintermuteUsage", "Unable to start usage worker", e)
                stopSelf()
            }
        }
    }

    private fun promote(): Boolean {
        val withLocation = signals.locationAllowed()
        val withUsage = signals.usageAllowed()
        if (!withLocation && !withUsage) return false
        val manager = getSystemService(NotificationManager::class.java)
        val channel = "usage_timeline"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channel, "移动端信息采集", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, channel)
            .setSmallIcon(R.drawable.ic_island_cat).setContentTitle(if (withLocation) "正在定时采集位置" else "正在记录前台应用活动")
            .setContentText("可在「信息采集」中调整或关闭。")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).build()
        if (Build.VERSION.SDK_INT >= 29) {
            var types = if (withLocation) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
            if (withUsage && Build.VERSION.SDK_INT >= 34) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            startForeground(58211, notification, types)
        } else startForeground(58211, notification)
        appliedFlags = flags(withUsage, withLocation)
        return true
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        signals.execute {
            try {
                val store = signals.store
                val reply = store.transaction {
                    if (!active || (!signals.usageAllowed() && !signals.locationAllowed())) {
                        main.post { stopSelf() }
                        return@transaction null
                    }
                    val scope = store["scope"] ?: return@transaction null
                    fun next(): Map<String, Any>? {
                        val row = store.batch(limit = 1).firstOrNull() ?: return null
                        return when (row["source"]) {
                            "usage" -> if (signals.usageAllowed()) row else store.batch("location", 1).firstOrNull()?.takeIf { signals.locationAllowed() }
                            "location" -> if (signals.locationAllowed()) row else store.batch("usage", 1).firstOrNull()?.takeIf { signals.usageAllowed() }
                            else -> null
                        }
                    }
                    when (call.method) {
                        "next" -> {
                            val now = System.currentTimeMillis()
                            if (signals.usageAllowed()) signals.usage.collect(now)
                            if (signals.locationAllowed()) signals.location.requestDueFix(now)
                            next()?.let { mapOf("scope" to scope, "row" to it) }
                        }
                        "visitFrame" -> if (scope == call.argument<String>("scope"))
                            signals.screenshots.visitFrame(scope, call.argument<String>("id").orEmpty()) else null
                        "canSend" -> scope == call.argument<String>("scope") && next()?.let {
                            it["id"] == call.argument<String>("id") &&
                                (it["hasVisitScreenshot"] == true) == (call.argument<Boolean>("withFrame") == true)
                        } == true
                        "ack" -> {
                            if (scope == call.argument<String>("scope")) {
                                store.ack(listOf(call.argument<String>("id")!!))
                                if (call.argument<String>("source") == "usage") store["usageUploadedAt"] = System.currentTimeMillis().toString()
                            }
                            null
                        }
                        else -> error("Unknown usage worker method")
                    }
                }
                main.post { if (active) result.success(reply) }
            } catch (e: Exception) {
                main.post { if (active) result.error("usage", e.message, null) }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (appliedFlags != flags(signals.usageAllowed(), signals.locationAllowed()) && !promote()) stopSelf()
        return START_STICKY
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        active = false
        running = false
        appliedFlags = 0
        engine?.destroy()
        super.onDestroy()
    }

    companion object {
        @Volatile var running = false
            private set

        @Volatile private var appliedFlags = 0
        private fun flags(usage: Boolean, location: Boolean) = (if (usage) 1 else 0) + (if (location) 2 else 0)
        fun configure(context: Context, usage: Boolean, location: Boolean) {
            val intent = Intent(context, UsageService::class.java)
            if (!usage && !location) {
                if (running) context.stopService(intent)
            } else if ((!running || appliedFlags != flags(usage, location)) && DeviceNotices.foreground) {
                try {
                    ContextCompat.startForegroundService(context, intent)
                } catch (_: IllegalStateException) {
                    // The activity may have just paused. Retry on the next visible configuration.
                }
            }
        }
    }
}
