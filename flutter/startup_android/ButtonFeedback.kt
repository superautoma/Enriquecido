package org.gestorherramientas.gestor_herramientas_quill_test

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.view.HapticFeedbackConstants
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Small preloaded click and standard, system-controlled haptic response. */
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
            if (call.method != "tap") {
                result.notImplemented()
            } else {
                if (call.argument<Boolean>("sound") == true) playClick()
                if (call.argument<Boolean>("vibration") == true) {
                    try {
                        activity.window.decorView.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    } catch (_: Exception) { /* Hardware feedback is optional. */ }
                }
                result.success(null)
            }
        }
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
