package dev.purin.purin_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/** A user-started session tracking today's agenda and the assistant's progress. */
internal class IslandNotifications(private val activity: MainActivity, val channel: MethodChannel) {
    companion object {
        const val OPEN = "dev.purin.OPEN_ISLAND"
        private const val CHANNEL = "assistant_island"
        private const val ID = 59732
    }

    private val manager = activity.getSystemService(NotificationManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var owner: String? = null
    private var promoted = false
    private var minimized = false
    private var lastContent: Pair<String, List<String>>? = null
    private val head by lazy {
        BitmapFactory.decodeResource(activity.resources, R.mipmap.ic_launcher)
    }

    init {
        clear()
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 36) {
            result.success(if (call.method == "fold") "unsupported" else null)
            return
        }
        try {
            when (call.method) {
                "fold" -> {
                    val token = requireNotNull(call.argument<String>("owner"))
                    manager.createNotificationChannel(NotificationChannel(CHANNEL, "助手实时胶囊", NotificationManager.IMPORTANCE_DEFAULT).apply {
                        setSound(null, null)
                        enableVibration(false)
                    })
                    if (!manager.areNotificationsEnabled() || manager.getNotificationChannel(CHANNEL).importance == NotificationManager.IMPORTANCE_NONE) {
                        result.success("disabled")
                        return
                    }
                    if (!manager.canPostPromotedNotifications()) {
                        result.success("notPromoted")
                        return
                    }
                    owner = token
                    promoted = false
                    lastContent = null
                    post(call.argument<String>("status") ?: "待机", emptyList())
                    confirmPromotion(token, result, 0)
                }
                "set" -> {
                    if (owner != null && owner == call.argument<String>("owner") && (!promoted || active())) {
                        post(call.argument<String>("status") ?: "待机", call.argument<List<String>>("lines").orEmpty())
                    }
                    result.success(null)
                }
                "active" -> result.success(owner == call.arguments && active())
                "clear" -> {
                    if (owner == call.arguments) clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: RuntimeException) {
            clear()
            result.error("island", e.localizedMessage, null)
        }
    }

    @android.annotation.TargetApi(36)
    private fun confirmPromotion(token: String, result: MethodChannel.Result, attempt: Int) {
        if (owner != token || activity.isFinishing || activity.isDestroyed) {
            result.success("cancelled")
            return
        }
        val posted = manager.activeNotifications.firstOrNull { it.id == ID }
        if (posted != null && posted.notification.flags and Notification.FLAG_PROMOTED_ONGOING != 0) {
            promoted = true
            minimized = activity.hasWindowFocus() && activity.moveTaskToBack(true)
            if (!minimized) clear()
            result.success(if (minimized) "promoted" else "unavailable")
        } else if (attempt < 10) {
            main.postDelayed({ confirmPromotion(token, result, attempt + 1) }, 100)
        } else {
            clear()
            result.success("notPromoted")
        }
    }

    @android.annotation.TargetApi(36)
    private fun post(status: String, lines: List<String>) {
        val content = status to lines
        if (content == lastContent) return
        val open = PendingIntent.getActivity(activity, ID, Intent(activity, MainActivity::class.java).apply {
            action = OPEN
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val chip = when (status) {
            "正在回复" -> "•••"
            "收到新回复" -> "✉"
            "有未读通知" -> "●"
            "消息需要处理", "未连接" -> "!"
            "处理已结束" -> "✓"
            else -> "☾"
        }
        val text = lines.joinToString("\n").ifBlank {
            if (status == "未连接") "连接后可查看今天的内容" else "正在读取今天的内容…"
        }
        val midnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val notification = Notification.Builder(activity, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_purin).setLargeIcon(head)
            .setContentTitle("今日通知与安排").setContentText(text.replace("\n", " · "))
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSubText("todo").setShortCriticalText(chip)
            .setOngoing(true).setOnlyAlertOnce(true).setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setContentIntent(open)
            .setTimeoutAfter((midnight.timeInMillis - System.currentTimeMillis()).coerceAtLeast(1L))
            .addExtras(Bundle().apply { putBoolean("android.requestPromotedOngoing", true) })
            .build()
        manager.notify(ID, notification)
        lastContent = content
    }

    private fun active() = manager.activeNotifications.any { it.id == ID }

    fun resumed() {
        if (!minimized) return
        clear()
        channel.invokeMethod("openChat", null)
    }

    fun clear() {
        owner = null
        promoted = false
        minimized = false
        lastContent = null
        manager.cancel(ID)
    }
}
