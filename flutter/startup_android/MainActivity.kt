package org.gestorherramientas.gestor_herramientas_quill_test

import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

class MainActivity : FlutterFragmentActivity() {
    private var loadingView: View? = null
    private var flutterVisible = false
    private var buttonFeedback: ButtonFeedback? = null
    private var toolAi: ToolAi? = null

    private val uiListener = object : FlutterUiDisplayListener {
        override fun onFlutterUiDisplayed() {
            runOnUiThread {
                flutterVisible = true
                loadingView?.let { (it.parent as? ViewGroup)?.removeView(it) }
                loadingView = null
            }
        }

        override fun onFlutterUiNoLongerDisplayed() = Unit
    }

    override fun createFlutterFragment(): FlutterFragment =
        FlutterFragment.withNewEngine()
            .dartEntrypoint(dartEntrypointFunctionName)
            .initialRoute(initialRoute)
            .renderMode(RenderMode.surface)
            .shouldAttachEngineToActivity(true)
            .shouldAutomaticallyHandleOnBackPressed(true)
            // Let Android draw the animated loader before Flutter's first frame.
            .shouldDelayFirstAndroidViewDraw(false)
            .build<FlutterFragment>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (flutterVisible) return

        val background = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(247, 249, 251))
            isClickable = true
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }
        content.addView(ProgressBar(this).apply {
            isIndeterminate = true
            indeterminateTintList = ColorStateList.valueOf(Color.rgb(22, 139, 210))
            contentDescription = "Cargando la aplicación"
        }, LinearLayout.LayoutParams(dp(42), dp(42)))
        content.addView(TextView(this).apply {
            text = "Gestor de herramientas"
            textSize = 22f
            setTextColor(Color.rgb(32, 36, 42))
            gravity = Gravity.CENTER
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(24) })
        content.addView(TextView(this).apply {
            text = "Cargando…"
            textSize = 14f
            setTextColor(Color.rgb(114, 119, 125))
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(12) })
        background.addView(content, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ))
        loadingView = background
        addContentView(background, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
        ))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ToolManagement.attach(this, flutterEngine)
        buttonFeedback = ButtonFeedback(this, flutterEngine)
        toolAi = ToolAi(this, flutterEngine)
        flutterEngine.renderer.addIsDisplayingFlutterUiListener(uiListener)
        if (flutterEngine.renderer.isDisplayingFlutterUi) {
            uiListener.onFlutterUiDisplayed()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        buttonFeedback?.dispose()
        buttonFeedback = null
        toolAi?.dispose()
        toolAi = null
        flutterEngine.renderer.removeIsDisplayingFlutterUiListener(uiListener)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density + 0.5f).toInt()
}
