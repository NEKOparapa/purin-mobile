package dev.purin.purin_mobile

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import java.io.File
import java.io.IOException
import java.util.Locale

// The Flutter DeviceStore saves the preference in the application support directory.
internal fun Context.purinStrings(language: String? = null): Resources {
    val tag = language ?: try {
        File(filesDir, "language").readText().trim()
    } catch (_: IOException) {
        "zh-CN"
    }
    val config = Configuration(resources.configuration)
    config.setLocale(if (tag == "en") Locale.ENGLISH else Locale.SIMPLIFIED_CHINESE)
    return createConfigurationContext(config).resources
}
