package dev.wintermute.wintermute_mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

internal class NoticeActions(private val activity: MainActivity, val channel: MethodChannel) {
    companion object {
        const val PERMISSION = 54810
        const val FILE = 54811
    }

    private var permission: MethodChannel.Result? = null
    private var download: Download? = null

    private data class Download(
        val url: URL,
        val deviceId: String,
        val installation: String?,
        val token: String,
        val bytes: Long,
        val result: MethodChannel.Result,
    )

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> {
                    val enabled = DeviceNotices.enabled(activity)
                    DeviceNotices.schedule(activity, enabled)
                    result.success(enabled)
                }
                "enable" -> {
                    if (Build.VERSION.SDK_INT >= 33 && !DeviceNotices.enabled(activity)) {
                        check(permission == null) { "授权窗口已打开" }
                        val prefs =
                            activity.getSharedPreferences(
                                "notice_permission",
                                Activity.MODE_PRIVATE,
                            )
                        if (
                            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                android.content.pm.PackageManager.PERMISSION_GRANTED &&
                                (!prefs.getBoolean("asked", false) ||
                                    activity.shouldShowRequestPermissionRationale(
                                        Manifest.permission.POST_NOTIFICATIONS
                                    ))
                        ) {
                            permission = result
                            prefs.edit().putBoolean("asked", true).apply()
                            activity.requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                PERMISSION,
                            )
                            return
                        }
                    }
                    if (!DeviceNotices.enabled(activity)) {
                        val intent =
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", activity.packageName, null),
                            )
                        activity.startActivity(intent)
                    }
                    permissionDone(result)
                }
                "foregroundArrival" ->
                    result.success(
                        if (DeviceNotices.foreground)
                            DeviceNotices.present(
                                activity,
                                call.argument<String>("scope")!!,
                                call.argument<String>("id")!!,
                                null,
                                null,
                            )
                        else null
                    )
                "dismiss" -> {
                    DeviceNotices.dismiss(
                        activity,
                        call.argument<String>("scope")!!,
                        call.argument<String>("id")!!,
                    )
                    result.success(null)
                }
                "takeOpen" -> {
                    val intent = activity.intent
                    if (intent?.action == DeviceNotices.OPEN) {
                        val scope = intent.getStringExtra("scope")
                        val id = intent.getStringExtra("id")
                        intent.action = null
                        result.success(
                            if (scope != null && id != null) mapOf("scope" to scope, "id" to id)
                            else null
                        )
                    } else result.success(null)
                }
                "saveAttachment" -> {
                    check(download == null) { "请等待当前文件保存完成" }
                    val size = call.argument<Number>("size")!!.toLong()
                    require(size in 0..8L * 1024 * 1024) { "附件大小超出限制" }
                    val url = URL(call.argument<String>("url")!!)
                    require(url.protocol in setOf("https", "http") && url.userInfo == null) {
                        "无效的下载地址"
                    }
                    val name =
                        call
                            .argument<String>("name")
                            .orEmpty()
                            .substringAfterLast('/')
                            .substringAfterLast('\\')
                            .filterNot { it.isISOControl() }
                            .trim()
                            .take(180)
                            .ifEmpty { "附件" }
                    // Prefer Android's extension mapping. Servers on Windows may
                    // report CSV as Excel, causing DocumentsUI to append ".xls".
                    val extension = name.substringAfterLast('.', "").lowercase()
                    val mime =
                        android.webkit.MimeTypeMap.getSingleton()
                            .getMimeTypeFromExtension(extension)
                            ?: call.argument<String>("type")?.takeIf {
                                extension.isEmpty() && it.contains('/')
                            }
                            ?: "*/*"
                    val chooser =
                        Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(mime)
                            .putExtra(Intent.EXTRA_TITLE, name)
                    val pending =
                        Download(
                            url,
                            call.argument<String>("deviceId")!!,
                            call.argument<String>("installation"),
                            call.argument<String>("token")!!,
                            size,
                            result,
                        )
                    activity.startActivityForResult(chooser, FILE)
                    download = pending
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            if (permission === result) permission = null
            result.error("device_notice", e.message, null)
        }
    }

    private fun permissionDone(result: MethodChannel.Result) {
        val enabled = DeviceNotices.enabled(activity)
        DeviceNotices.schedule(activity, enabled)
        result.success(enabled)
    }

    fun permissionResult() {
        val reply = permission
        permission = null
        if (reply != null) permissionDone(reply)
    }

    fun fileResult(resultCode: Int, data: Intent?) {
        val pending = download ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            download = null
            pending.result.success(false)
            return
        }
        if (uri.scheme != "content") {
            download = null
            pending.result.error("save", "文件提供方无效", null)
            return
        }
        Thread {
                var temp: File? = null
                try {
                    val staging =
                        File.createTempFile("notification-", ".partial", activity.cacheDir)
                    temp = staging
                    val http = (pending.url.openConnection() as HttpURLConnection)
                    try {
                        http.instanceFollowRedirects = false
                        http.connectTimeout = 8000
                        http.readTimeout = 20000
                        http.useCaches = false
                        http.setRequestProperty("Authorization", "Bearer " + pending.token)
                        http.setRequestProperty("X-Device-ID", pending.deviceId)
                        pending.installation?.let { http.setRequestProperty("X-Device-Instance", it) }
                        check(http.responseCode == 200) { "下载失败 (HTTP ${http.responseCode})" }
                        http.inputStream.use { src ->
                            staging.outputStream().use { dst ->
                                val buffer = ByteArray(32768)
                                var total = 0L
                                while (true) {
                                    val count = src.read(buffer)
                                    if (count < 0) break
                                    total += count
                                    check(total <= pending.bytes) { "附件大小不匹配" }
                                    dst.write(buffer, 0, count)
                                }
                                check(total == pending.bytes) { "附件下载不完整" }
                            }
                        }
                    } finally {
                        http.disconnect()
                    }
                    val out =
                        activity.contentResolver.openOutputStream(uri, "wt") ?: error("无法写入选择的位置")
                    out.use { dest -> staging.inputStream().use { it.copyTo(dest) } }
                    activity.runOnUiThread {
                        download = null
                        pending.result.success(true)
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread {
                        download = null
                        pending.result.error("save", e.message, null)
                    }
                } finally {
                    temp?.delete()
                }
            }
            .start()
    }
}
