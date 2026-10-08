package org.gestorherramientas.gestor_herramientas_quill_test

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Device-aware vibration with a legacy fallback and an independent hardware test. */
class ButtonFeedback(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger,
        "org.gestorherramientas/button_feedback")
    private var pool: SoundPool? = null
    private var soundId = 0
    private var ready = false

    init {
        try {
            pool = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            ).build().also { soundPool ->
                soundPool.setOnLoadCompleteListener { _, _, status -> ready = status == 0 }
                soundId = soundPool.load(activity, R.raw.button_click, 1)
            }
        } catch (_: Exception) {
            pool?.release()
            pool = null
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "tap" -> {
                    if (call.argument<Boolean>("sound") == true) playClick()
                    if (call.argument<Boolean>("vibration") == true) vibrate(120L)
                    result.success(null)
                }
                "vibrationStatus" -> result.success(vibrationStatus())
                "testVibration" -> {
                    val status = vibrate(1000L)
                    Log.i("ButtonFeedback", "Manual vibration test: ${status["status"]}")
                    result.success(status)
                }
                "openVibrationSettings" -> result.success(openSettings())
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun deviceVibrator(): Vibrator? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val manager = activity.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                if (manager != null) {
                    val defaultVibrator = manager.defaultVibrator
                    if (defaultVibrator.hasVibrator()) return defaultVibrator
                    for (id in manager.vibratorIds) {
                        val vibrator = manager.getVibrator(id)
                        if (vibrator.hasVibrator()) return vibrator
                    }
                }
            } catch (_: Exception) { /* Try the service available on older devices. */ }
        }
        return activity.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    @Suppress("DEPRECATION")
    private fun vibrationStatus(): Map<String, Any?> {
        return try {
            val vibrator = deviceVibrator()
            val enabled = Settings.System.getInt(activity.contentResolver,
                Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) != 0
            val intensity = Settings.System.getInt(activity.contentResolver,
                "haptic_feedback_intensity", -1)
            val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
            val version = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
                else info.versionCode.toLong()
            mapOf("hasVibrator" to (vibrator?.hasVibrator() == true),
                "permissionGranted" to (activity.checkSelfPermission(Manifest.permission.VIBRATE)
                    == PackageManager.PERMISSION_GRANTED),
                "touchFeedbackEnabled" to (enabled && intensity != 0),
                "appVersion" to version)
        } catch (_: Exception) {
            mapOf("status" to "unavailable")
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(duration: Long): Map<String, Any?> {
        val status = vibrationStatus()
        if (status["hasVibrator"] != true) {
            return status + ("status" to if (status["hasVibrator"] == false) "no_motor" else "unavailable")
        }
        if (status["permissionGranted"] != true) return status + ("status" to "permission_denied")
        if (status["touchFeedbackEnabled"] == false) return status + ("status" to "system_disabled")
        return try {
            val vibrator = deviceVibrator() ?: return status + ("status" to "unavailable")
            val timings = longArrayOf(0L, duration)
            var route = "legacy"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    // Timings-only effects also work on motors without amplitude control.
                    val effect = VibrationEffect.createWaveform(timings, -1)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        vibrator.vibrate(effect, VibrationAttributes.Builder()
                            .setUsage(VibrationAttributes.USAGE_TOUCH).build())
                    } else {
                        vibrator.vibrate(effect, AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).build())
                    }
                    route = "waveform"
                } catch (error: SecurityException) {
                    throw error
                } catch (_: Exception) {
                    vibrator.vibrate(timings, -1)
                }
            } else {
                vibrator.vibrate(timings, -1)
            }
            status + mapOf("status" to "requested", "durationMs" to duration, "route" to route)
        } catch (_: SecurityException) {
            status + ("status" to "permission_denied")
        } catch (_: Exception) {
            status + ("status" to "unavailable")
        }
    }

    private fun openSettings(): Boolean {
        for (action in listOf(Settings.ACTION_SOUND_SETTINGS, Settings.ACTION_SETTINGS)) {
            try {
                activity.startActivity(Intent(action))
                return true
            } catch (_: Exception) { /* Some manufacturers have a different settings activity. */ }
        }
        return false
    }

    private fun playClick() {
        try {
            val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL && ready) {
                pool?.play(soundId, 0.45f, 0.45f, 1, 0, 1.0f)
            }
        } catch (_: Exception) { /* Sound must never block an inventory action. */ }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pool?.release()
        pool = null
        ready = false
    }
}
