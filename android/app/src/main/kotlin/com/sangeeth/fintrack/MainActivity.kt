package com.sangeeth.fintrack

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.sangeeth.fintrack/native_bridge"
    private var methodChannel: MethodChannel? = null
    private var pendingSharedPayload: Map<String, String>? = null
    private var pendingNotificationRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
        // Initialize reminders by default on app creation
        ReminderScheduler.reschedule(applicationContext)
        handleNotificationIntent(intent)
        handleIncomingIntent(intent, isNewIntent = false)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        val route = intent?.getStringExtra("route")
        if (!route.isNullOrBlank()) {
            pendingNotificationRoute = route
            methodChannel?.invokeMethod("onNotificationRoute", route)
        }
    }

    private fun enableHighRefreshRate() {
        try {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                this.display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return

            val modes = display.supportedModes
            val currentMode = display.mode
            var bestMode = currentMode
            for (mode in modes) {
                if (mode.physicalWidth == currentMode.physicalWidth &&
                    mode.physicalHeight == currentMode.physicalHeight &&
                    mode.refreshRate > bestMode.refreshRate
                ) {
                    bestMode = mode
                }
            }
            if (bestMode.modeId != currentMode.modeId) {
                val params = window.attributes
                params.preferredDisplayModeId = bestMode.modeId
                window.attributes = params
            }
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedPayload" -> {
                    val payload = pendingSharedPayload
                    pendingSharedPayload = null
                    result.success(payload)
                }
                "setSecureScreen" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (enabled) {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "getPendingNotificationRoute" -> {
                    val route = pendingNotificationRoute
                    pendingNotificationRoute = null
                    result.success(route)
                }
                "scheduleExpenseReminders" -> {
                    val interval = call.argument<Int>("intervalHours") ?: 3
                    val night = call.argument<Boolean>("nightReminder") ?: true
                    ReminderScheduler.schedule(applicationContext, interval, night)
                    result.success(true)
                }
                "cancelExpenseReminders" -> {
                    ReminderScheduler.cancel(applicationContext)
                    result.success(true)
                }
                "showTestReminder" -> {
                    ReminderScheduler.sendTestNotification(applicationContext)
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                101
                            )
                        }
                    }
                    result.success(true)
                }
                "hasSmsPermission" -> {
                    // Play-Protect-safe Smart Clipboard & Share Intent SMS mode requires no dangerous permissions
                    result.success(true)
                }
                "requestSmsPermission" -> {
                    result.success(true)
                }
                "readRecentBankSms" -> {
                    result.success(emptyList<Map<String, Any>>())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
        handleIncomingIntent(intent, isNewIntent = true)
    }

    private fun handleIncomingIntent(intent: Intent?, isNewIntent: Boolean) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type ?: return

        if (Intent.ACTION_SEND == action) {
            val payload: Map<String, String>? = when {
                type.startsWith("image/") -> {
                    val imageUri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_STREAM)
                    }
                    imageUri?.let { copyUriToCache(it, "shared_screenshot.jpg") }?.let { path ->
                        mapOf("type" to "image", "path" to path)
                    }
                }
                type.startsWith("text/") -> {
                    val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (!sharedText.isNullOrBlank()) {
                        mapOf("type" to "text", "text" to sharedText)
                    } else null
                }
                type == "application/pdf" -> {
                    val pdfUri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_STREAM)
                    }
                    pdfUri?.let { copyUriToCache(it, "shared_statement.pdf") }?.let { path ->
                        mapOf("type" to "pdf", "path" to path)
                    }
                }
                else -> null
            }

            if (payload != null) {
                if (isNewIntent && methodChannel != null) {
                    methodChannel?.invokeMethod("onSharedPayload", payload)
                } else {
                    pendingSharedPayload = payload
                }
            }
        }
    }

    private fun copyUriToCache(uri: Uri, fileName: String): String? {
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val outFile = File(cacheDir, "${System.currentTimeMillis()}_$fileName")
            FileOutputStream(outFile).use { output ->
                inputStream.copyTo(output)
            }
            inputStream.close()
            outFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
