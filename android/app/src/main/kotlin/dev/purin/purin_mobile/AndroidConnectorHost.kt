package dev.purin.purin_mobile

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class AndroidConnectorHost(private val activity: MainActivity) {
    private val signals = MobileSignals.get(activity)
    private val files = ConnectorFiles(activity)
    private val queries = ConnectorQueries(activity)
    private val worker = Executors.newSingleThreadExecutor()
    private val prefs = activity.getSharedPreferences("connector_permissions", Activity.MODE_PRIVATE)
    private val groups = mapOf(
        "clock" to listOf("android_set_alarm", "android_start_timer"),
        "usage" to listOf("android_app_usage"),
        "calendar" to listOf("android_calendar_events", "android_calendar_create"),
        "contacts" to listOf("android_contacts"),
        "files" to listOf("android_files_list", "android_files_read"),
        "location" to listOf("android_location"),
        "notifications" to listOf("android_notifications"),
        "sms" to listOf("android_sms"),
    )
    private val runtime = mapOf(
        "calendar" to arrayOf(Manifest.permission.READ_CALENDAR),
        "contacts" to arrayOf(Manifest.permission.READ_CONTACTS),
        "sms" to arrayOf(Manifest.permission.READ_SMS),
        "location" to arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION),
    )
    private data class Request(val id: String, val scope: String, val result: MethodChannel.Result)
    private var pending: Request? = null

    private fun granted(id: String, scope: String): Boolean = when (id) {
        "clock" -> true
        "usage" -> signals.usage.granted()
        "location" -> signals.location.granted() && signals.location.enabled()
        "files" -> files.root(scope) != null
        "notifications" -> if (Build.VERSION.SDK_INT >= 27) {
            activity.getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(
                ComponentName(activity, ConnectorNotificationListener::class.java))
        } else NotificationManagerCompat.getEnabledListenerPackages(activity).contains(activity.packageName)
        else -> runtime.getValue(id).all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            val scope = call.argument<String>("scope").orEmpty()
            require(scope.isNotBlank()) { "设备连接为空" }
            when (call.method) {
                "access" -> result.success(groups.keys.associateWith { granted(it, scope) })
                "releaseFolder" -> { files.forget(scope); result.success(null) }
                "authorize" -> authorize(call.argument<String>("id").orEmpty(), scope, result)
                "execute" -> {
                    val tool = call.argument<String>("tool").orEmpty()
                    val group = groups.entries.singleOrNull { tool in it.value }?.key ?: error("未知工具")
                    check(DeviceNotices.foreground && granted(group, scope)) { "请在手机前台打开并授权此连接器" }
                    val args = ConnectorArgs(call.argument<Map<String, Any?>>("args").orEmpty())
                    if (group == "clock" || tool == "android_calendar_create") {
                        activity.startActivity(intent(tool, args))
                        result.success(mapOf("status" to "opened", "message" to "已交给系统应用，请在手机上查看"))
                    } else worker.execute {
                        try {
                            check(granted(group, scope)) { "系统授权已撤销" }
                            val value = when (group) {
                                "files" -> files.execute(scope, tool, args)
                                "notifications" -> ConnectorNotificationListener.query(args)
                                else -> queries.execute(tool, args)
                            }
                            activity.runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            activity.runOnUiThread { failure(result, e) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            if (pending?.result === result) pending = null
            failure(result, e)
        }
    }

    private fun failure(result: MethodChannel.Result, error: Exception) {
        val message = when (error) {
            is android.content.ActivityNotFoundException -> "手机上没有可处理此操作的系统应用"
            is SecurityException -> "系统拒绝访问，请检查该项授权"
            is IllegalArgumentException, is IllegalStateException -> error.message?.take(160)
            else -> "设备暂时无法完成此操作"
        }
        result.error("android_connector", message, null)
    }

    private fun authorize(id: String, scope: String, result: MethodChannel.Result) {
        require(id in groups)
        if (granted(id, scope)) { result.success(true); return }
        check(pending == null) { "已有授权窗口打开" }
        pending = Request(id, scope, result)
        val settings = when (id) {
            "files" -> Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            "usage" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "notifications" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            "location" -> if (signals.location.granted()) Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS) else null
            else -> null
        }
        if (settings != null) {
            activity.startActivityForResult(settings, SETTINGS)
            return
        }
        val permissions = runtime.getValue(id)
        if (prefs.getBoolean(id, false) && permissions.none(activity::shouldShowRequestPermissionRationale)) {
            val uri = Uri.fromParts("package", activity.packageName, null)
            activity.startActivityForResult(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri), SETTINGS)
        } else {
            prefs.edit().putBoolean(id, true).apply()
            activity.requestPermissions(permissions, PERMISSION)
        }
    }

    fun finish(resultCode: Int = Activity.RESULT_CANCELED, data: Intent? = null) {
        val request = pending ?: return
        pending = null
        try {
            if (request.id == "files" && resultCode == Activity.RESULT_OK) {
                data?.data?.let { files.remember(request.scope, it) }
            }
            request.result.success(granted(request.id, request.scope))
        } catch (e: Exception) { failure(request.result, e) }
    }

    private fun intent(tool: String, args: ConnectorArgs): Intent = when (tool) {
        "android_set_alarm" -> Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, args.number("hour", 0..23))
            .putExtra(AlarmClock.EXTRA_MINUTES, args.number("minute", 0..59))
            .putExtra(AlarmClock.EXTRA_MESSAGE, args.text("label", 120))
        "android_start_timer" -> Intent(AlarmClock.ACTION_SET_TIMER)
            .putExtra(AlarmClock.EXTRA_LENGTH, args.number("seconds", 1..86400))
            .putExtra(AlarmClock.EXTRA_MESSAGE, args.text("label", 120))
        "android_calendar_create" -> {
            val (start, end) = args.window()
            Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI)
                .putExtra(CalendarContract.Events.TITLE, args.text("title", 200, true))
                .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
                .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                .putExtra(CalendarContract.Events.EVENT_LOCATION, args.text("location", 200))
        }
        else -> error("未知操作")
    }

    fun close() {
        worker.shutdownNow()
        pending?.result?.error("interrupted", "授权窗口已关闭", null)
        pending = null
    }

    companion object {
        const val SETTINGS = 54224
        const val PERMISSION = 54225
    }
}

internal class ConnectorArgs(private val args: Map<String, Any?>) {
    fun text(key: String, max: Int, required: Boolean = false): String {
        val value = args[key] ?: ""
        require(value is String && value.length <= max && (!required || value.isNotBlank())) { "无效的参数 $key" }
        return value
    }
    fun number(key: String, range: IntRange, default: Int? = null): Int {
        val value = args[key] ?: default
        require(value is Int && value in range) { "无效的参数 $key" }
        return value
    }
    val limit: Int get() = number("limit", 1..30, 10)
    fun window(): Pair<Long, Long> {
        fun millis(key: String): Long {
            val value = args[key]
            require(value is Int || value is Long) { "需要 Unix 毫秒时间" }
            return (value as Number).toLong().also { require(it in 0L..4102444800000L) }
        }
        val start = millis("start_ms")
        val end = millis("end_ms")
        require(end - start in 1L..31L * 86400000L) { "时间范围须在 31 天内" }
        return start to end
    }
}
