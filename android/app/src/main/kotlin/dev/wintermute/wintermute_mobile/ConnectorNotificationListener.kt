package dev.wintermute.wintermute_mobile

import android.app.Notification
import android.service.notification.NotificationListenerService

class ConnectorNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() { super.onListenerConnected(); current = this }
    override fun onListenerDisconnected() { clear(); super.onListenerDisconnected() }
    override fun onDestroy() { clear(); super.onDestroy() }
    private fun clear() { if (current === this) current = null }

    companion object {
        @Volatile private var current: ConnectorNotificationListener? = null

        internal fun query(args: ConnectorArgs): Map<String, Any> {
            val service = current ?: error("通知监听服务尚未连接，请检查系统通知使用权")
            val pkg = args.text("package", 200)
            val notifications = (service.activeNotifications ?: error("暂时无法读取通知栏"))
                .filter { pkg.isEmpty() || it.packageName == pkg }.sortedByDescending { it.postTime }
            val items = notifications.take(args.limit).map {
                val extras = it.notification.extras
                val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT)
                mapOf("package" to it.packageName, "posted_ms" to it.postTime,
                    "title" to extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.take(160),
                    "text" to text?.toString()?.take(250))
            }
            return mapOf("items" to items, "truncated" to (items.size < notifications.size))
        }
    }
}
