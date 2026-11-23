package dev.wintermute.wintermute_mobile

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.media.projection.MediaProjectionManager
import android.media.projection.MediaProjectionConfig
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val signals by lazy { MobileSignals.get(this) }
    private var permissionResult: MethodChannel.Result? = null
    private var shotResult: MethodChannel.Result? = null
    private var shotToken: String? = null
    private var shotChannel: MethodChannel? = null
    private var notices: NoticeActions? = null
    private var connectors: AndroidConnectorHost? = null
    private var connectorChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        connectors = AndroidConnectorHost(this).also { host ->
            connectorChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.wintermute/android_connectors")
                .also { it.setMethodCallHandler(host::handle) }
        }
        val noticeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DeviceNotices.CHANNEL)
        notices = NoticeActions(this, noticeChannel).also { noticeChannel.setMethodCallHandler(it::handle) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.wintermute/mobile_signals")
            .setMethodCallHandler(::onSignalMethod)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.wintermute/screenshots")
        shotChannel = channel
        signals.screenshots.channel = channel
        channel.setMethodCallHandler(::onScreenshotMethod)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        connectorChannel?.setMethodCallHandler(null)
        connectorChannel = null
        connectors?.close()
        connectors = null
        notices?.channel?.setMethodCallHandler(null)
        notices = null
        if (signals.screenshots.channel === shotChannel) signals.screenshots.channel = null
        shotChannel?.setMethodCallHandler(null)
        shotChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if(intent.action==DeviceNotices.OPEN) notices?.channel?.invokeMethod("openNotice",null)
    }

    override fun onResume(){super.onResume();DeviceNotices.foreground=true}
    override fun onPause(){DeviceNotices.foreground=false;super.onPause()}

    private fun onScreenshotMethod(call: MethodCall, result: MethodChannel.Result) {
        val shots = signals.screenshots
        if (call.method == "request") {
            try {
                check(shotResult == null) { "已有屏幕共享授权窗口打开" }
                val manager = getSystemService(MediaProjectionManager::class.java)
                // A selected single app could display a different app from the current usage span.
                val intent = if (Build.VERSION.SDK_INT >= 34) manager.createScreenCaptureIntent(
                    MediaProjectionConfig.createConfigForDefaultDisplay()) else manager.createScreenCaptureIntent()
                shotToken = shots.beginConsent()
                shotResult = result
                startActivityForResult(intent, SCREENSHOT_REQUEST)
            } catch (error: RuntimeException) {
                if (shotResult === result) shotResult = null
                result.error("projection", error.message, null)
            }
            return
        }
        signals.execute {
            try {
                val scope = call.argument<String>("scope").orEmpty()
                val value: Any? = when (call.method) {
                    "configure" -> shots.configure(scope, call.argument<Boolean>("enabled") == true,
                        call.argument<Int>("intervalSeconds") ?: 300)
                    "read" -> shots.read(scope)
                    "bytes" -> shots.bytes(scope, call.argument<String>("id").orEmpty())
                    "ack" -> { shots.ack(scope, call.argument<List<String>>("ids").orEmpty()); null }
                    else -> { runOnUiThread { result.notImplemented() }; return@execute }
                }
                runOnUiThread { result.success(value) }
            } catch (error: RuntimeException) {
                runOnUiThread { result.error("screenshots", error.message, null) }
            }
        }
    }

    private fun onSignalMethod(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "deviceName") {
            result.success(Build.MODEL)
            return
        }
        if (call.method == "request" || call.method == "settings") {
            try {
                permission(call.argument<String>("source").orEmpty(), call.method == "settings", result)
            } catch (error: Exception) {
                permissionResult = null
                result.error("permission", error.message, null)
            }
            return
        }
        signals.execute {
            try {
                val scope = call.argument<String>("scope").orEmpty()
                val value: Any? = when (call.method) {
                    "configure" -> {
                        signals.configure(scope, call.argument<Boolean>("location") == true,
                            call.argument<Boolean>("usage") == true)
                        signals.status(this)
                    }
                    "status" -> signals.status(this)
                    "read" -> signals.read(scope)
                    "ack" -> {
                        signals.ack(scope, call.argument<List<String>>("ids").orEmpty())
                        null
                    }
                    else -> {
                        runOnUiThread { result.notImplemented() }
                        return@execute
                    }
                }
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread { result.error("mobile_signals", error.message, null) }
            }
        }
    }

    private fun permission(source: String, settings: Boolean, result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("busy", "已有授权窗口打开", null)
            return
        }
        permissionResult = result
        val appUri = Uri.parse("package:" + packageName)
        val appSettings = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, appUri)
        when (source) {
            "usage" -> {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                try {
                    startActivityForResult(Intent(intent).setData(appUri), SETTINGS_REQUEST)
                } catch (_: ActivityNotFoundException) {
                    startActivityForResult(intent, SETTINGS_REQUEST)
                }
            }
            "location" -> when {
                signals.location.granted() && !signals.location.enabled() ->
                    startActivityForResult(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS), SETTINGS_REQUEST)
                settings -> startActivityForResult(appSettings, SETTINGS_REQUEST)
                signals.location.granted() -> finishRequest()
                else -> requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.ACCESS_FINE_LOCATION), LOCATION_REQUEST)
            }
            "backgroundLocation" -> when {
                signals.location.background() -> finishRequest()
                !signals.location.granted() -> finishRequest()
                Build.VERSION.SDK_INT == 29 && !settings ->
                    requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), BACKGROUND_REQUEST)
                else -> startActivityForResult(appSettings, SETTINGS_REQUEST)
            }
            else -> throw IllegalArgumentException("未知授权类型")
        }
    }

    private fun finishRequest() {
        val pending = permissionResult
        permissionResult = null
        pending?.success(null)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == AndroidConnectorHost.PERMISSION) connectors?.finish()
        if(requestCode==NoticeActions.PERMISSION) notices?.permissionResult()
        if (requestCode == LOCATION_REQUEST || requestCode == BACKGROUND_REQUEST) {
            if (requestCode == LOCATION_REQUEST && grantResults.isNotEmpty()) {
                signals.execute {
                    signals.store["askedLocation"] = "true"
                    runOnUiThread { finishRequest() }
                }
            } else finishRequest()
        }
    }

    @Deprecated("Used by Android system settings")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == AndroidConnectorHost.SETTINGS) connectors?.finish(resultCode, data)
        if(requestCode==NoticeActions.FILE) notices?.fileResult(resultCode,data)
        if (requestCode == SETTINGS_REQUEST) finishRequest()
        if (requestCode == SCREENSHOT_REQUEST) {
            val reply = shotResult
            val token = shotToken
            shotResult = null
            shotToken = null
            try {
                if (token != null && signals.screenshots.generation == token) {
                    if (resultCode == RESULT_OK && data != null) {
                        val intent = Intent(this, ScreenshotService::class.java)
                            .putExtra("grant", data).putExtra("token", token)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                    } else signals.screenshots.denied(token)
                }
                reply?.success(null)
            } catch (error: RuntimeException) {
                if (token != null) signals.screenshots.denied(token)
                reply?.error("projection", error.message, null)
            }
        }
    }

    companion object {
        private const val LOCATION_REQUEST = 54210
        private const val BACKGROUND_REQUEST = 54211
        private const val SETTINGS_REQUEST = 54212
        private const val SCREENSHOT_REQUEST = 54213
    }
}
